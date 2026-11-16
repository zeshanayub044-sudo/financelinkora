"use server";

import { z } from "zod";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { journalDraftSchema } from "@/lib/validation";

async function getAuthed() {
  const supabase = await createClient();
  if (!supabase) throw new Error("Supabase is not configured.");
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) throw new Error("Sign in to continue.");
  return { supabase, user };
}

function refreshAccounting() {
  for (const path of ["/dashboard", "/approvals", "/journal-entries", "/ledger", "/trial-balance", "/reports", "/statements"]) revalidatePath(path);
}

export async function createJournalAction(input: unknown) {
  const parsed = journalDraftSchema.safeParse(input);
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Check the entry details." };
  const { supabase } = await getAuthed();
  const value = parsed.data;
  const { data: org, error: orgError } = await supabase.from("organizations").select("base_currency").eq("id", value.org_id).single();
  if (orgError) return { error: orgError.message };
  if (value.currency !== org.base_currency || value.exchange_rate !== 1) return { error: `Journal entries must use the organization base currency (${org.base_currency}) until FX revaluation reports are implemented.` };
  const { data, error } = await supabase.rpc("create_journal_entry_draft", {
    p_org: value.org_id,
    p_entry_date: value.entry_date,
    p_reference: value.reference || null,
    p_description: value.description,
    p_currency: value.currency,
    p_exchange_rate: value.exchange_rate,
    p_entry_kind: "general",
    p_lines: value.lines.map(line => ({ account_id: line.account_id, debit: line.debit, credit: line.credit, memo: line.memo || null })),
  });
  if (error) return { error: error.message };
  refreshAccounting();
  return { id: data };
}

async function entryRpc(name: "submit_journal_entry" | "queue_journal_entry" | "approve_journal_entry" | "post_journal_entry", entryId: string) {
  const { supabase } = await getAuthed();
  const { error } = await supabase.rpc(name, { p_entry: entryId } as never);
  if (error) return { error: error.message };
  refreshAccounting();
  return { ok: true };
}

export async function submitAction(id: string) { return entryRpc("submit_journal_entry", id); }
export async function queueAction(id: string) { return entryRpc("queue_journal_entry", id); }
export async function approveAction(id: string) { return entryRpc("approve_journal_entry", id); }
export async function postAction(id: string) { return entryRpc("post_journal_entry", id); }

export async function rejectAction(entryId: string, reason: string) {
  const parsed = z.string().trim().min(1, "A rejection reason is required.").max(2000).safeParse(reason);
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Enter a rejection reason." };
  const { supabase } = await getAuthed();
  const { error } = await supabase.rpc("reject_journal_entry", { p_entry: entryId, p_reason: parsed.data });
  if (error) return { error: error.message };
  refreshAccounting();
  return { ok: true };
}

export async function reverseAction(entryId: string, date: string, reason: string) {
  const schema = z.object({ date: z.iso.date(), reason: z.string().trim().min(1, "A reversal reason is required.").max(2000) });
  const parsed = schema.safeParse({ date, reason });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Check the reversal details." };
  const { supabase } = await getAuthed();
  const { data, error } = await supabase.rpc("reverse_journal_entry", { p_entry: entryId, p_date: parsed.data.date, p_reason: parsed.data.reason });
  if (error) return { error: error.message };
  refreshAccounting();
  return { id: data };
}

export async function createAccountAction(input: { org_id: string; code: string; name: string; type: "asset" | "liability" | "equity" | "revenue" | "expense"; description: string }) {
  const schema = z.object({ org_id: z.string().uuid(), code: z.string().trim().min(1).max(30), name: z.string().trim().min(2).max(150), type: z.enum(["asset", "liability", "equity", "revenue", "expense"]), description: z.string().max(500) });
  const v = schema.safeParse(input);
  if (!v.success) return { error: v.error.issues[0]?.message };
  const { supabase } = await getAuthed();
  const { error } = await supabase.from("accounts").insert({ ...v.data, description: v.data.description || null });
  if (error) return { error: error.message };
  revalidatePath("/accounts");
  return { ok: true };
}

export async function setPeriodClosedAction(id: string, closed: boolean) {
  const { supabase } = await getAuthed();
  const { error } = await supabase.from("accounting_periods").update({ is_closed: closed }).eq("id", id);
  if (error) return { error: error.message };
  revalidatePath("/periods");
  return { ok: true };
}

export async function createPeriodAction(input: { org_id: string; start_date: string; end_date: string }) {
  const schema = z.object({ org_id: z.string().uuid(), start_date: z.iso.date(), end_date: z.iso.date() }).refine(x => x.end_date >= x.start_date, "End date must be on or after start date.");
  const v = schema.safeParse(input);
  if (!v.success) return { error: v.error.issues[0]?.message };
  const { supabase } = await getAuthed();
  const { error } = await supabase.from("accounting_periods").insert({ ...v.data, is_closed: false });
  if (error) return { error: error.message };
  revalidatePath("/periods");
  return { ok: true };
}

export async function setApprovalRequirementAction(orgId: string, required: boolean) {
  const { supabase } = await getAuthed();
  const { error } = await supabase.from("organizations").update({ require_approval: required }).eq("id", orgId);
  if (error) return { error: error.message };
  revalidatePath("/settings");
  return { ok: true };
}

