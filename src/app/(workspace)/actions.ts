"use server";

import { z } from "zod";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { accountReportingClassSchema, budgetDraftSchema, businessJournalSchema, journalDraftSchema } from "@/lib/validation";

async function getAuthed() {
  const supabase = await createClient();
  if (!supabase) throw new Error("Supabase is not configured.");
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) throw new Error("Sign in to continue.");
  return { supabase, user };
}

function refreshAccounting() {
  for (const path of ["/dashboard", "/approvals", "/journal-entries", "/income", "/expenses", "/banking", "/ledger", "/trial-balance", "/reports", "/reports/ratios", "/statements", "/budgets", "/tax", "/invoices", "/suppliers"]) revalidatePath(path);
}
function normalizeRate(value:string){return value.includes(".")?value.replace(/0+$/g,"").replace(/\.$/,""):value;}

export async function createBudgetAction(input: unknown) {
  const parsed=budgetDraftSchema.safeParse(input);
  if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the budget details."};
  const {supabase}=await getAuthed();const value=parsed.data;
  const {data,error}=await supabase.rpc("create_budget_draft",{
    p_org:value.org_id,p_name:value.name,p_start:value.start_date,p_end:value.end_date,
    p_lines:value.lines.map(line=>({account_id:line.account_id,period_start:line.period_start,amount:line.amount})),
  });
  if(error)return {error:error.message};
  refreshAccounting();return {id:data};
}

const partySchema=z.object({org_id:z.string().uuid(),party_type:z.enum(["customer","supplier"]),name:z.string().trim().min(2).max(200),email:z.email().max(254).or(z.literal("")).optional(),phone:z.string().max(60).or(z.literal("")).optional()});
const documentSchema=z.object({org_id:z.string().uuid(),document_type:z.enum(["invoice","bill"]),party_id:z.string().uuid(),document_number:z.string().trim().min(1).max(80),issue_date:z.iso.date(),due_date:z.iso.date(),control_account_id:z.string().uuid(),lines:z.array(z.object({account_id:z.string().uuid(),amount:z.string().regex(/^(?:0|[1-9]\d{0,15})(?:\.\d{1,4})?$/).refine(v=>/[1-9]/.test(v),"Amount must be greater than zero."),description:z.string().trim().min(1).max(500),tax_code_id:z.string().uuid().or(z.literal("")).nullable().optional()})).min(1).max(1000)}).refine(v=>v.due_date>=v.issue_date,{path:["due_date"],message:"Due date cannot precede the issue date."});
const paymentSchema=z.object({document_id:z.string().uuid(),payment_date:z.iso.date(),account_id:z.string().uuid(),amount:z.string().regex(/^(?:0|[1-9]\d{0,15})(?:\.\d{1,4})?$/).refine(v=>/[1-9]/.test(v),"Amount must be greater than zero."),reference:z.string().max(120).optional()});

export async function createFinancialPartyAction(input:unknown){
  const parsed=partySchema.safeParse(input);if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the customer or supplier details."};
  const {supabase}=await getAuthed();const v=parsed.data;
  const {data,error}=await supabase.rpc("create_financial_party",{p_org:v.org_id,p_party_type:v.party_type,p_name:v.name,p_email:v.email||null,p_phone:v.phone||null});
  if(error)return {error:error.message};for(const p of ["/customers","/suppliers","/invoices","/payments"])revalidatePath(p);return {id:data};
}
export async function createFinancialDocumentAction(input:unknown){
  const parsed=documentSchema.safeParse(input);if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the document details."};
  const {supabase}=await getAuthed();const v=parsed.data;
  const {data,error}=await supabase.rpc("create_financial_document_draft",{p_org:v.org_id,p_document_type:v.document_type,p_party:v.party_id,p_document_number:v.document_number,p_issue_date:v.issue_date,p_due_date:v.due_date,p_control_account:v.control_account_id,p_lines:v.lines.map(line=>({...line,tax_code_id:line.tax_code_id||null}))});
  if(error)return {error:error.message};revalidatePath(v.document_type==="invoice"?"/invoices":"/suppliers");return {id:data};
}
export async function updateFinancialDocumentDraftAction(documentId:string,input:unknown){
  const id=z.string().uuid().safeParse(documentId);if(!id.success)return {error:"Invalid document."};
  const parsed=documentSchema.safeParse(input);if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the document details."};
  const {supabase}=await getAuthed();const v=parsed.data;
  const {error}=await supabase.rpc("update_financial_document_draft",{p_document:id.data,p_party:v.party_id,p_document_number:v.document_number,p_issue_date:v.issue_date,p_due_date:v.due_date,p_control_account:v.control_account_id,p_lines:v.lines.map(line=>({...line,tax_code_id:line.tax_code_id||null}))});
  if(error)return {error:error.message};revalidatePath("/invoices");revalidatePath("/suppliers");return {ok:true};
}
export async function submitFinancialDocumentAction(documentId:string){
  const parsed=z.string().uuid().safeParse(documentId);if(!parsed.success)return {error:"Invalid document."};const {supabase}=await getAuthed();
  const {data,error}=await supabase.rpc("submit_financial_document",{p_document:parsed.data});if(error)return {error:error.message};
  revalidatePath("/invoices");revalidatePath("/suppliers");revalidatePath("/approvals");return {id:data};
}
export async function recordFinancialDocumentPaymentAction(input:unknown){
  const parsed=paymentSchema.safeParse(input);if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the payment details."};const {supabase}=await getAuthed();const v=parsed.data;
  const {data,error}=await supabase.rpc("record_financial_document_payment",{p_document:v.document_id,p_payment_date:v.payment_date,p_account:v.account_id,p_amount:v.amount,p_reference:v.reference||null});
  if(error)return {error:error.message};revalidatePath("/payments");revalidatePath("/invoices");revalidatePath("/suppliers");revalidatePath("/approvals");return {id:data};
}
export async function resubmitFinancialDocumentPaymentAction(paymentId:string){
  const parsed=z.string().uuid().safeParse(paymentId);if(!parsed.success)return {error:"Invalid payment."};const {supabase}=await getAuthed();
  const {data,error}=await supabase.rpc("resubmit_financial_document_payment",{p_payment:parsed.data});if(error)return {error:error.message};
  for(const path of ["/payments","/invoices","/suppliers","/approvals","/dashboard"])revalidatePath(path);return {id:data};
}
export async function correctFinancialDocumentPaymentAction(input:unknown){
 const parsed=z.object({payment_id:z.string().uuid(),payment_date:z.iso.date(),account_id:z.string().uuid(),amount:z.string().regex(/^(?:0|[1-9]\d{0,15})(?:\.\d{1,4})?$/).refine(v=>/[1-9]/.test(v),"Amount must be greater than zero."),reference:z.string().max(120)}).safeParse(input);
 if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the corrected payment details."};const {supabase}=await getAuthed();const v=parsed.data;
 const {data,error}=await supabase.rpc("correct_and_resubmit_financial_document_payment",{p_payment:v.payment_id,p_payment_date:v.payment_date,p_account:v.account_id,p_amount:v.amount,p_reference:v.reference||null});if(error)return {error:error.message};
 for(const path of ["/payments","/invoices","/suppliers","/approvals","/dashboard"])revalidatePath(path);return {id:data};
}

export async function updateBudgetAction(budgetId: string,input: unknown) {
  const parsed=budgetDraftSchema.safeParse(input);
  if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the budget details."};
  const id=z.string().uuid().safeParse(budgetId);
  if(!id.success)return {error:"Invalid budget."};
  const {supabase}=await getAuthed();const value=parsed.data;
  const {error}=await supabase.rpc("update_budget_draft",{
    p_budget:id.data,p_name:value.name,p_start:value.start_date,p_end:value.end_date,
    p_lines:value.lines.map(line=>({account_id:line.account_id,period_start:line.period_start,amount:line.amount})),
  });
  if(error)return {error:error.message};
  refreshAccounting();return {ok:true};
}

export async function approveBudgetAction(budgetId: string) {
  const parsed=z.string().uuid().safeParse(budgetId);
  if(!parsed.success)return {error:"Invalid budget."};
  const {supabase}=await getAuthed();
  const {error}=await supabase.rpc("approve_budget",{p_budget:parsed.data});
  if(error)return {error:error.message};
  refreshAccounting();return {ok:true};
}

export async function createBusinessJournalAction(input: unknown) {
  const parsed = businessJournalSchema.safeParse(input);
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Check the transaction details." };
  const { supabase } = await getAuthed();
  const value = parsed.data;
  const { data: org, error: orgError } = await supabase.from("organizations").select("base_currency").eq("id", value.org_id).single();
  if (orgError) return { error: orgError.message };
  const lines = value.kind === "income"||value.kind==="bank_deposit"
    ? [{ account_id: value.asset_account_id, debit: value.amount, credit: 0, memo: null }, { account_id: value.account_id, debit: 0, credit: value.amount, memo: null }]
    : value.kind === "expense"||value.kind==="bank_withdrawal"
      ? [{ account_id: value.account_id, debit: value.amount, credit: 0, memo: null }, { account_id: value.asset_account_id, debit: 0, credit: value.amount, memo: null }]
      : [{ account_id: value.destination_account_id, debit: value.amount, credit: 0, memo: "Transfer received" }, { account_id: value.source_account_id, debit: 0, credit: value.amount, memo: "Transfer sent" }];
  const { data, error } = await supabase.rpc("create_journal_entry_draft", {
    p_org: value.org_id, p_entry_date: value.entry_date, p_reference: value.reference || null,
    p_description: value.description, p_currency: org.base_currency, p_exchange_rate: 1,
    p_entry_kind: value.kind, p_lines: lines,
  });
  if (error) return { error: error.message };
  refreshAccounting();
  return { id: data };
}

const importedStatementRowSchema=z.object({
  date:z.iso.date(),description:z.string().trim().min(1).max(500),reference:z.string().max(120).nullable(),
  amount:z.string().regex(/^-?(?:0|[1-9]\d{0,15})(?:\.\d{1,4})?$/).refine(value=>/[1-9]/.test(value),"Statement amounts must be non-zero."),
});
const statementBalanceSchema=z.string().regex(/^-?(0|[1-9]\d{0,15})(\.\d{1,4})?$/,"Enter a finite balance with at most four decimal places.");
const importStatementSchema=z.object({org_id:z.string().uuid(),account_id:z.string().uuid(),file_name:z.string().trim().min(1).max(255),start_date:z.iso.date(),end_date:z.iso.date(),opening_balance:statementBalanceSchema,closing_balance:statementBalanceSchema,rows:z.array(importedStatementRowSchema).min(1).max(5000)}).superRefine((value,ctx)=>{
  if(value.start_date>value.end_date)ctx.addIssue({code:"custom",path:["end_date"],message:"Statement end date must be on or after its start date."});
  if(value.rows.some(row=>row.date<value.start_date||row.date>value.end_date))ctx.addIssue({code:"custom",path:["rows"],message:"Every CSV row must fall within the statement date range."});
});

export async function importBankStatementAction(input:unknown){
  const parsed=importStatementSchema.safeParse(input);
  if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the statement rows."};
  const {supabase}=await getAuthed();
  const {data,error}=await supabase.rpc("import_bank_statement",{
    p_org:parsed.data.org_id,p_account:parsed.data.account_id,p_file_name:parsed.data.file_name,
    p_start_date:parsed.data.start_date,p_end_date:parsed.data.end_date,
    p_opening_balance:parsed.data.opening_balance,p_closing_balance:parsed.data.closing_balance,
    p_rows:parsed.data.rows.map(row=>({date:row.date,description:row.description,reference:row.reference,amount:row.amount})),
  });
  if(error)return {error:error.message};
  revalidatePath("/banking");return {id:data};
}

export async function matchBankStatementRowAction(rowId:string,journalLineId:string|null){
  const parsed=z.object({row_id:z.string().uuid(),journal_line_id:z.string().uuid().nullable()}).safeParse({row_id:rowId,journal_line_id:journalLineId});
  if(!parsed.success)return {error:"Invalid statement match."};
  const {supabase}=await getAuthed();
  const {error}=await supabase.rpc("match_bank_statement_row",{p_row:parsed.data.row_id,p_journal_line:parsed.data.journal_line_id});
  if(error)return {error:error.message};
  revalidatePath("/banking");return {ok:true};
}

export async function createJournalAction(input: unknown) {
  const parsed = journalDraftSchema.safeParse(input);
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Check the entry details." };
  if (parsed.data.entry_kind !== "general" && parsed.data.entry_kind !== "opening_balance") return { error: "Choose an entry type supported by this journal form." };
  const { supabase } = await getAuthed();
  const value = parsed.data;
  const { data: org, error: orgError } = await supabase.from("organizations").select("base_currency").eq("id", value.org_id).single();
  if (orgError) return { error: orgError.message };
  const normalizedRate=normalizeRate(value.exchange_rate);
  if (value.currency === org.base_currency && normalizedRate !== "1") return { error: `Entries in the organization base currency (${org.base_currency}) must use an exchange rate of 1.` };
  const { data, error } = await supabase.rpc("create_journal_entry_draft", {
    p_org: value.org_id,
    p_entry_date: value.entry_date,
    p_reference: value.reference || null,
    p_description: value.description,
    p_currency: value.currency,
    p_exchange_rate: value.exchange_rate,
    p_entry_kind: value.entry_kind,
    p_lines: value.lines.map(line => ({ account_id: line.account_id, debit: line.debit, credit: line.credit, memo: line.memo || null, department_id:line.department_id||null,project_id:line.project_id||null })),
  });
  if (error) return { error: error.message };
  refreshAccounting();
  return { id: data };
}

export async function updateJournalAction(entryId: string, input: unknown) {
  const parsed = journalDraftSchema.safeParse(input);
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Check the entry details." };
  const { supabase } = await getAuthed();
  const value = parsed.data;
  const {data:existing,error:entryError}=await supabase.rpc("journal_exchange_rate_exact",{p_entry:entryId});
  if(entryError)return {error:entryError.message};
  if(!existing?.[0])return {error:"Journal draft not found."};
  if(existing[0].currency!==value.currency||normalizeRate(existing[0].exchange_rate)!==normalizeRate(value.exchange_rate))return {error:"Transaction currency and exchange rate are fixed when a draft is created."};
  const { error } = await supabase.rpc("update_journal_entry_draft", {
    p_entry: entryId,
    p_entry_date: value.entry_date,
    p_reference: value.reference || null,
    p_description: value.description,
    p_lines: value.lines.map(line => ({ account_id: line.account_id, debit: line.debit, credit: line.credit, memo: line.memo || null, department_id:line.department_id||null,project_id:line.project_id||null })),
  });
  if (error) return { error: error.message };
  refreshAccounting();
  revalidatePath(`/journal-entries/${entryId}`);
  return { ok: true };
}

async function entryRpc(name: "submit_journal_entry" | "queue_journal_entry" | "approve_journal_entry" | "post_journal_entry", entryId: string) {
  const { supabase } = await getAuthed();
  let errorMessage: string | undefined;
  switch (name) {
    case "submit_journal_entry": errorMessage = (await supabase.rpc("submit_journal_entry", { p_entry: entryId })).error?.message; break;
    case "queue_journal_entry": errorMessage = (await supabase.rpc("queue_journal_entry", { p_entry: entryId })).error?.message; break;
    case "approve_journal_entry": errorMessage = (await supabase.rpc("approve_journal_entry", { p_entry: entryId })).error?.message; break;
    case "post_journal_entry": errorMessage = (await supabase.rpc("post_journal_entry", { p_entry: entryId })).error?.message; break;
  }
  if (errorMessage) return { error: errorMessage };
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

type AccountReportingClass="cash"|"bank"|"receivable"|"payable"|"accumulated_depreciation";
export async function createAccountAction(input: { org_id: string; code: string; name: string; type: "asset" | "liability" | "equity" | "revenue" | "expense"; description: string; reporting_class?:AccountReportingClass|null }) {
  const schema = z.object({ org_id: z.string().uuid(), code: z.string().trim().min(1).max(30), name: z.string().trim().min(2).max(150), type: z.enum(["asset", "liability", "equity", "revenue", "expense"]), description: z.string().max(500), reporting_class:z.enum(["cash","bank","receivable","payable","accumulated_depreciation"]).nullable().optional() });
  const v = schema.safeParse(input);
  if (!v.success) return { error: v.error.issues[0]?.message };
  const classification=accountReportingClassSchema.safeParse({type:v.data.type,reporting_class:v.data.reporting_class??null});
  if(!classification.success)return {error:classification.error.issues[0]?.message};
  const { supabase } = await getAuthed();
  const { error } = await supabase.from("accounts").insert({ ...v.data, description: v.data.description || null,reporting_class:v.data.reporting_class??null });
  if (error) return { error: error.message };
  revalidatePath("/accounts");
  return { ok: true };
}

export async function updateAccountReportingClassAction(input:{org_id:string;account_id:string;reporting_class:AccountReportingClass|null;type:"asset"|"liability"|"equity"|"revenue"|"expense"}){
  const schema=z.object({org_id:z.string().uuid(),account_id:z.string().uuid(),reporting_class:z.enum(["cash","bank","receivable","payable","accumulated_depreciation"]).nullable(),type:z.enum(["asset","liability","equity","revenue","expense"])});
  const parsed=schema.safeParse(input);if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Invalid account classification."};
  const classification=accountReportingClassSchema.safeParse({type:parsed.data.type,reporting_class:parsed.data.reporting_class});
  if(!classification.success)return {error:classification.error.issues[0]?.message??"Invalid account classification."};
  const {supabase}=await getAuthed();
  const {error}=await supabase.from("accounts").update({reporting_class:parsed.data.reporting_class,...(parsed.data.reporting_class==="receivable"||parsed.data.reporting_class==="payable"?{cash_flow_class:"operating" as const}:{})}).eq("id",parsed.data.account_id).eq("org_id",parsed.data.org_id);
  if(error)return {error:error.message};
  revalidatePath("/accounts");revalidatePath("/dashboard");return {ok:true};
}

export async function updateAccountCashFlowClassAction(input:{org_id:string;account_id:string;cash_flow_class:"operating"|"investing"|"financing"|"unclassified"}){
  const schema=z.object({org_id:z.string().uuid(),account_id:z.string().uuid(),cash_flow_class:z.enum(["operating","investing","financing","unclassified"])});
  const parsed=schema.safeParse(input);if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Invalid cash-flow classification."};
  const {supabase}=await getAuthed();
  const {error}=await supabase.from("accounts").update({cash_flow_class:parsed.data.cash_flow_class}).eq("id",parsed.data.account_id).eq("org_id",parsed.data.org_id);
  if(error)return {error:error.message};
  revalidatePath("/accounts");revalidatePath("/cash-flow");return {ok:true};
}

const fixedAssetSchema=z.object({
  org_id:z.string().uuid(),asset_code:z.string().trim().min(1).max(40),name:z.string().trim().min(2).max(200),description:z.string().trim().max(1000).optional(),
  acquisition_date:z.iso.date(),in_service_date:z.iso.date(),cost:z.string().regex(/^(?:0|[1-9]\d{0,15})(?:\.\d{1,4})?$/).refine(v=>/[1-9]/.test(v),"Cost must be greater than zero."),
  residual_value:z.string().regex(/^(?:0|[1-9]\d{0,15})(?:\.\d{1,4})?$/),useful_life_months:z.coerce.number().int().min(1).max(1200),
  asset_account_id:z.string().uuid(),accumulated_depreciation_account_id:z.string().uuid(),depreciation_expense_account_id:z.string().uuid(),acquisition_entry_id:z.string().uuid(),
}).refine(v=>v.in_service_date>=v.acquisition_date,{path:["in_service_date"],message:"In-service date cannot precede acquisition date."});
export async function registerFixedAssetAction(input:unknown){
  const parsed=fixedAssetSchema.safeParse(input);if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the asset details."};
  const {supabase}=await getAuthed();const v=parsed.data;
  const {data,error}=await supabase.rpc("register_fixed_asset",{p_org:v.org_id,p_asset_code:v.asset_code,p_name:v.name,p_description:v.description||null,
    p_acquisition_date:v.acquisition_date,p_in_service_date:v.in_service_date,p_cost:v.cost,p_residual_value:v.residual_value,p_useful_life_months:v.useful_life_months,
    p_asset_account:v.asset_account_id,p_accumulated_depreciation_account:v.accumulated_depreciation_account_id,
    p_depreciation_expense_account:v.depreciation_expense_account_id,p_acquisition_entry:v.acquisition_entry_id});
  if(error)return {error:error.message};revalidatePath("/fixed-assets");revalidatePath("/accounts");return {id:data};
}
export async function createFixedAssetDepreciationAction(orgId:string,periodEnd:string){
  const parsed=z.object({org_id:z.string().uuid(),period_end:z.iso.date()}).safeParse({org_id:orgId,period_end:periodEnd});
  if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Choose a valid month end."};const {supabase}=await getAuthed();
  const {data,error}=await supabase.rpc("create_fixed_asset_depreciation_draft",{p_org:parsed.data.org_id,p_period_end:parsed.data.period_end});
  if(error)return {error:error.message};revalidatePath("/fixed-assets");revalidatePath("/journal-entries");revalidatePath("/approvals");return {id:data};
}
export async function createFixedAssetDisposalAction(input:unknown){
  const parsed=z.object({org_id:z.string().uuid(),asset_id:z.string().uuid(),disposal_date:z.iso.date(),proceeds:z.string().regex(/^(?:0|[1-9]\d{0,15})(?:\.\d{1,4})?$/),proceeds_account_id:z.string().uuid().nullable(),gain_account_id:z.string().uuid().nullable(),loss_account_id:z.string().uuid().nullable()}).safeParse(input);
  if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the disposal details."};const {supabase}=await getAuthed();const v=parsed.data;
  const {data,error}=await supabase.rpc("create_fixed_asset_disposal_draft",{p_org:v.org_id,p_asset:v.asset_id,p_disposal_date:v.disposal_date,p_proceeds:v.proceeds,p_proceeds_account:v.proceeds_account_id,p_gain_account:v.gain_account_id,p_loss_account:v.loss_account_id});
  if(error)return {error:error.message};revalidatePath("/fixed-assets");revalidatePath("/journal-entries");revalidatePath("/approvals");return {id:data};
}

export async function setPeriodClosedAction(id: string, closed: boolean) {
  const { supabase } = await getAuthed();
  const { error } = await supabase.from("accounting_periods").update({ is_closed: closed }).eq("id", id);
  if (error) return { error: error.message };
  revalidatePath("/periods");
  return { ok: true };
}

export async function createFiscalYearCloseAction(input:unknown){
  const parsed=z.object({org_id:z.string().uuid(),period_id:z.string().uuid(),retained_earnings_account_id:z.string().uuid()}).safeParse(input);
  if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the fiscal year closing details."};
  const {supabase}=await getAuthed();const {data,error}=await supabase.rpc("create_fiscal_year_close_draft",{
    p_org:parsed.data.org_id,p_period:parsed.data.period_id,p_retained_earnings_account:parsed.data.retained_earnings_account_id,
  });
  if(error)return {error:error.message};
  revalidatePath("/periods");revalidatePath("/journal-entries");revalidatePath("/approvals");revalidatePath("/statements");revalidatePath("/dashboard");
  return {id:data};
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

const memberRoleSchema=z.enum(["owner","administrator","finance_manager","accountant","approver","auditor","viewer","employee"]);
const memberChangeSchema=z.object({org_id:z.string().uuid(),user_id:z.string().uuid(),role:memberRoleSchema});

export async function addOrganizationMemberAction(input:unknown){
  const parsed=memberChangeSchema.safeParse(input);
  if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the member details."};
  const {supabase}=await getAuthed();const {org_id,user_id,role}=parsed.data;
  const {error}=await supabase.rpc("add_organization_member",{p_org:org_id,p_user:user_id,p_role:role});
  if(error)return {error:error.message};revalidatePath("/settings");return {ok:true};
}

export async function setOrganizationMemberRoleAction(input:unknown){
  const parsed=memberChangeSchema.safeParse(input);
  if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the member details."};
  const {supabase}=await getAuthed();const {org_id,user_id,role}=parsed.data;
  const {error}=await supabase.rpc("set_organization_member_role",{p_org:org_id,p_user:user_id,p_role:role});
  if(error)return {error:error.message};revalidatePath("/settings");return {ok:true};
}

export async function removeOrganizationMemberAction(orgId:string,userId:string){
  const parsed=z.object({org_id:z.string().uuid(),user_id:z.string().uuid()}).safeParse({org_id:orgId,user_id:userId});
  if(!parsed.success)return {error:"Invalid organization member."};
  const {supabase}=await getAuthed();
  const {error}=await supabase.rpc("remove_organization_member",{p_org:parsed.data.org_id,p_user:parsed.data.user_id});
  if(error)return {error:error.message};revalidatePath("/settings");return {ok:true};
}

const financialDimensionSchema=z.discriminatedUnion("kind",[
  z.object({kind:z.literal("department"),org_id:z.string().uuid(),code:z.string().trim().min(1).max(40),name:z.string().trim().min(2).max(200),description:z.string().trim().max(1000).optional()}),
  z.object({kind:z.literal("project"),org_id:z.string().uuid(),code:z.string().trim().min(1).max(40),name:z.string().trim().min(2).max(200),description:z.string().trim().max(1000).optional(),start_date:z.iso.date().or(z.literal("")).optional(),end_date:z.iso.date().or(z.literal("")).optional()}).refine(v=>!v.start_date||!v.end_date||v.end_date>=v.start_date,{path:["end_date"],message:"End date cannot precede start date."}),
]);
export async function createFinancialDimensionAction(input:unknown){
  const parsed=financialDimensionSchema.safeParse(input);if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the dimension details."};
  const {supabase}=await getAuthed();const v=parsed.data;
  const result=v.kind==="department"
    ?await supabase.rpc("create_department",{p_org:v.org_id,p_code:v.code,p_name:v.name,p_description:v.description||null})
    :await supabase.rpc("create_project",{p_org:v.org_id,p_code:v.code,p_name:v.name,p_description:v.description||null,p_start:v.start_date||null,p_end:v.end_date||null});
  if(result.error)return {error:result.error.message};
  const path=v.kind==="department"?"/departments":"/projects";revalidatePath(path);revalidatePath("/journal-entries/new");return {id:result.data};
}
export async function setFinancialDimensionActiveAction(input:{org_id:string;kind:"department"|"project";id:string;is_active:boolean}){
  const parsed=z.object({org_id:z.string().uuid(),kind:z.enum(["department","project"]),id:z.string().uuid(),is_active:z.boolean()}).safeParse(input);
  if(!parsed.success)return {error:"Invalid dimension."};const {supabase}=await getAuthed();const v=parsed.data;
  const result=v.kind==="department"
    ?await supabase.rpc("set_department_active",{p_org:v.org_id,p_department:v.id,p_active:v.is_active})
    :await supabase.rpc("set_project_active",{p_org:v.org_id,p_project:v.id,p_active:v.is_active});
  if(result.error)return {error:result.error.message};revalidatePath(v.kind==="department"?"/departments":"/projects");revalidatePath("/journal-entries/new");return {ok:true};
}

const taxCodeSchema=z.object({org_id:z.string().uuid(),code:z.string().trim().min(1).max(40),name:z.string().trim().min(2).max(200),scope:z.enum(["sales","purchases","both"]),rate:z.string().regex(/^(?:0|[1-9]\d{0,2})(?:\.\d{1,6})?$/),sales_account_id:z.string().uuid().or(z.literal("")),purchase_account_id:z.string().uuid().or(z.literal("")),effective_from:z.iso.date(),effective_to:z.iso.date().or(z.literal(""))}).refine(v=>!v.effective_to||v.effective_to>=v.effective_from,{path:["effective_to"],message:"End date cannot precede start date."});
export async function createTaxCodeAction(input:unknown){
  const parsed=taxCodeSchema.safeParse(input);if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the tax code details."};
  const {supabase}=await getAuthed();const v=parsed.data;
  const {data,error}=await supabase.rpc("create_tax_code",{p_org:v.org_id,p_code:v.code,p_name:v.name,p_scope:v.scope,p_rate:v.rate,p_sales_account:v.sales_account_id||null,p_purchase_account:v.purchase_account_id||null,p_effective_from:v.effective_from,p_effective_to:v.effective_to||null});
  if(error)return {error:error.message};revalidatePath("/tax");revalidatePath("/invoices");revalidatePath("/suppliers");return {id:data};
}
export async function setTaxCodeActiveAction(input:{org_id:string;tax_code_id:string;is_active:boolean}){
  const parsed=z.object({org_id:z.string().uuid(),tax_code_id:z.string().uuid(),is_active:z.boolean()}).safeParse(input);
  if(!parsed.success)return {error:"Invalid tax code."};const {supabase}=await getAuthed();
  const {error}=await supabase.rpc("set_tax_code_active",{p_org:parsed.data.org_id,p_tax_code:parsed.data.tax_code_id,p_active:parsed.data.is_active});
  if(error)return {error:error.message};for(const path of ["/tax","/invoices","/suppliers"])revalidatePath(path);return {ok:true};
}

const payrollEmployeeSchema=z.object({org_id:z.string().uuid(),code:z.string().trim().min(1).max(40).regex(/^[A-Za-z0-9][A-Za-z0-9._-]*$/),name:z.string().trim().min(2).max(200),start_date:z.iso.date(),email:z.email().max(254).or(z.literal(""))});
const payrollComponentSchema=z.object({org_id:z.string().uuid(),code:z.string().trim().min(1).max(40).regex(/^[A-Za-z0-9][A-Za-z0-9._-]*$/),name:z.string().trim().min(2).max(200),component_type:z.enum(["earning","deduction"]),account_id:z.string().uuid()});
const payrollRunSchema=z.object({org_id:z.string().uuid(),reference:z.string().trim().min(1).max(80),period_start:z.iso.date(),period_end:z.iso.date(),payable_account_id:z.string().uuid(),lines:z.array(z.object({employee_id:z.string().uuid(),component_id:z.string().uuid(),amount:z.string().regex(/^(?:0|[1-9]\d{0,15})(?:\.\d{1,4})?$/).refine(v=>/[1-9]/.test(v),"Amount must be greater than zero.")})).min(1).max(2000)});
export async function createPayrollEmployeeAction(input:unknown){
  const parsed=payrollEmployeeSchema.safeParse(input);if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the employee details."};
  const {supabase}=await getAuthed();const v=parsed.data;const {data,error}=await supabase.rpc("create_payroll_employee",{p_org:v.org_id,p_code:v.code,p_name:v.name,p_start:v.start_date,p_email:v.email||null});
  if(error)return {error:error.message};revalidatePath("/payroll");return {id:data};
}
export async function createPayrollComponentAction(input:unknown){
  const parsed=payrollComponentSchema.safeParse(input);if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the component details."};
  const {supabase}=await getAuthed();const v=parsed.data;const {data,error}=await supabase.rpc("create_payroll_component",{p_org:v.org_id,p_code:v.code,p_name:v.name,p_type:v.component_type,p_account:v.account_id});
  if(error)return {error:error.message};revalidatePath("/payroll");return {id:data};
}
export async function createPayrollRunAction(input:unknown){
  const parsed=payrollRunSchema.safeParse(input);if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the payroll run details."};
  const {supabase}=await getAuthed();const v=parsed.data;const {data,error}=await supabase.rpc("create_payroll_run_draft",{p_org:v.org_id,p_reference:v.reference,p_period_start:v.period_start,p_period_end:v.period_end,p_payable_account:v.payable_account_id,p_lines:v.lines});
  if(error)return {error:error.message};revalidatePath("/payroll");return {id:data};
}
export async function submitPayrollRunAction(runId:string){
  const parsed=z.string().uuid().safeParse(runId);if(!parsed.success)return {error:"Invalid payroll run."};const {supabase}=await getAuthed();
  const {data,error}=await supabase.rpc("submit_payroll_run",{p_run:parsed.data});if(error)return {error:error.message};
  for(const path of ["/payroll","/journal-entries","/approvals","/dashboard"])revalidatePath(path);return {id:data};
}
export async function updatePayrollRunAction(input:unknown){
  const parsed=z.object({run_id:z.string().uuid(),lines:z.array(z.object({employee_id:z.string().uuid(),component_id:z.string().uuid(),amount:z.string().regex(/^(?:0|[1-9]\d{0,15})(?:\.\d{1,4})?$/).refine(v=>/[1-9]/.test(v),"Amount must be greater than zero.")})).min(1).max(2000)}).safeParse(input);
  if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the payroll details."};const {supabase}=await getAuthed();
  const {error}=await supabase.rpc("update_payroll_run_draft",{p_run:parsed.data.run_id,p_lines:parsed.data.lines});if(error)return {error:error.message};revalidatePath("/payroll");return {ok:true};
}

const recurringTemplateSchema=z.object({org_id:z.string().uuid(),name:z.string().trim().min(2).max(200),kind:z.enum(["income","expense"]),frequency:z.enum(["monthly","quarterly","annually"]),start_date:z.iso.date(),end_date:z.iso.date().or(z.literal("")),amount:z.string().regex(/^(?:0|[1-9]\d{0,15})(?:\.\d{1,4})?$/).refine(v=>/[1-9]/.test(v),"Amount must be greater than zero."),category_account_id:z.string().uuid(),asset_account_id:z.string().uuid(),description:z.string().trim().min(2).max(500),reference_prefix:z.string().max(100)}).refine(v=>!v.end_date||v.end_date>=v.start_date,{path:["end_date"],message:"End date cannot precede the start date."});
export async function createRecurringTemplateAction(input:unknown){
 const parsed=recurringTemplateSchema.safeParse(input);if(!parsed.success)return {error:parsed.error.issues[0]?.message??"Check the recurring schedule details."};const {supabase}=await getAuthed();const v=parsed.data;
 const {data,error}=await supabase.rpc("create_recurring_template",{p_org:v.org_id,p_name:v.name,p_kind:v.kind,p_frequency:v.frequency,p_start:v.start_date,p_end:v.end_date||null,p_amount:v.amount,p_category_account:v.category_account_id,p_asset_account:v.asset_account_id,p_description:v.description,p_reference_prefix:v.reference_prefix});
 if(error)return {error:error.message};revalidatePath(v.kind==="income"?"/income":"/expenses");return {id:data};
}
export async function generateRecurringDraftAction(input:{org_id:string;template_id:string;scheduled_date:string}){
 const parsed=z.object({org_id:z.string().uuid(),template_id:z.string().uuid(),scheduled_date:z.iso.date()}).safeParse(input);if(!parsed.success)return {error:"Invalid scheduled occurrence."};const {supabase}=await getAuthed();
 const {data,error}=await supabase.rpc("generate_recurring_journal_draft",{p_org:parsed.data.org_id,p_template:parsed.data.template_id,p_scheduled_date:parsed.data.scheduled_date});if(error)return {error:error.message};
 refreshAccounting();for(const path of ["/income","/expenses"])revalidatePath(path);return {id:data};
}
export async function setRecurringTemplateActiveAction(input:{org_id:string;template_id:string;is_active:boolean;kind:"income"|"expense"}){
 const parsed=z.object({org_id:z.string().uuid(),template_id:z.string().uuid(),is_active:z.boolean(),kind:z.enum(["income","expense"])}).safeParse(input);if(!parsed.success)return {error:"Invalid recurring template."};const {supabase}=await getAuthed();
 const {error}=await supabase.rpc("set_recurring_template_active",{p_org:parsed.data.org_id,p_template:parsed.data.template_id,p_active:parsed.data.is_active});if(error)return {error:error.message};revalidatePath(parsed.data.kind==="income"?"/income":"/expenses");return {ok:true};
}
