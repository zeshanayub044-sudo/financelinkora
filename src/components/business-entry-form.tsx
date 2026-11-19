"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { createBusinessJournalAction } from "@/app/(workspace)/actions";
import { Button, Input, Label, Select } from "@/components/ui";

type Account = { id: string; code: string; name: string; type: string; reporting_class?:string|null;is_active?:boolean };
type Props = { orgId: string; kind: "income" | "expense" | "bank_transfer" | "bank_deposit" | "bank_withdrawal"; accounts: Account[] };
const today = new Date().toISOString().slice(0, 10);

export function BusinessEntryForm({ orgId, kind, accounts }: Props) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState("");
  const [date, setDate] = useState(today);
  const [description, setDescription] = useState("");
  const [reference, setReference] = useState("");
  const [amount, setAmount] = useState("");
  const [accountId, setAccountId] = useState("");
  const [assetId, setAssetId] = useState("");
  const [destinationId, setDestinationId] = useState("");
  const activeAccounts=accounts.filter(a=>a.is_active!==false);
  const assets = activeAccounts.filter(a => a.type === "asset");
  const cashBankAssets = assets.filter(a=>["cash","bank"].includes(a.reporting_class??""));
  const movementAssets = kind==="bank_deposit"||kind==="bank_withdrawal"||kind==="bank_transfer"?cashBankAssets:assets;
  const targetAccounts = kind === "income" ? activeAccounts.filter(a => a.type === "revenue") : kind === "expense" ? activeAccounts.filter(a => a.type === "expense") : activeAccounts.filter(a => !(a.type === "asset" && ["cash","bank"].includes(a.reporting_class??"")));
  const selectAccounts = (options: Account[], value: string, setValue: (id: string) => void, label: string) => {
    const id = `${kind}-${label.toLowerCase().replaceAll(/[^a-z0-9]+/g, "-")}`;
    return <div><Label htmlFor={id}>{label}</Label><Select id={id} required value={value} onChange={e => setValue(e.target.value)}><option value="">Select account</option>{options.map(a => <option key={a.id} value={a.id}>{a.code} · {a.name}</option>)}</Select></div>;
  };
  function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setError("");
    const input = kind === "bank_transfer"
      ? { kind, org_id: orgId, entry_date: date, description, reference, amount, source_account_id: assetId, destination_account_id: destinationId }
      : { kind, org_id: orgId, entry_date: date, description, reference, amount, account_id: accountId, asset_account_id: assetId };
    startTransition(async () => {
      try {
        const result = await createBusinessJournalAction(input);
        if ("error" in result && result.error) { setError(result.error); return; }
        if ("id" in result && result.id) router.push(`/journal-entries/${result.id}`);
      } catch {
        setError("Unable to save this draft because the request failed. Your entries are still in this form; please try again.");
      }
    });
  }
  return <form onSubmit={submit} className="grid gap-4 md:grid-cols-2">
    <div><Label htmlFor={`${kind}-date`}>Transaction date</Label><Input id={`${kind}-date`} type="date" required value={date} onChange={e => setDate(e.target.value)} /></div>
    <div><Label htmlFor={`${kind}-amount`}>Amount</Label><Input id={`${kind}-amount`} inputMode="decimal" placeholder="0.00" required value={amount} onChange={e => setAmount(e.target.value)} /></div>
    <div className="md:col-span-2"><Label htmlFor={`${kind}-description`}>Description</Label><Input id={`${kind}-description`} required minLength={2} maxLength={500} value={description} onChange={e => setDescription(e.target.value)} /></div>
    <div><Label htmlFor={`${kind}-reference`}>Reference (optional)</Label><Input id={`${kind}-reference`} maxLength={120} value={reference} onChange={e => setReference(e.target.value)} /></div>
    {kind === "bank_transfer" ? <>
      {selectAccounts(movementAssets, assetId, setAssetId, "From cash/bank account")}
      {selectAccounts(movementAssets.filter(a => a.id !== assetId), destinationId, setDestinationId, "To cash/bank account")}
      <p className="text-xs text-slate-500 md:col-span-2">Transfers debit the destination and credit the source account. They are not income or expenses. Only active accounts classified as cash or bank are selectable, and the database enforces the same rule.</p>
    </> : kind === "bank_deposit" ? <>
      {selectAccounts(movementAssets, assetId, setAssetId, "Receiving cash/bank account")}
      {selectAccounts(targetAccounts, accountId, setAccountId, "Offset account")}
      <p className="text-xs text-slate-500 md:col-span-2">A deposit debits a classified cash/bank account and credits its counter-account. Choose revenue only when the deposit is income; customer receipts should be recorded against receivables.</p>
    </> : kind === "bank_withdrawal" ? <>
      {selectAccounts(movementAssets, assetId, setAssetId, "Paying cash/bank account")}
      {selectAccounts(targetAccounts, accountId, setAccountId, "Offset account")}
      <p className="text-xs text-slate-500 md:col-span-2">A withdrawal debits its counter-account and credits classified cash/bank. Choose an expense only when it is an expense; supplier bill payments should be recorded against payables.</p>
    </> : <>
      {selectAccounts(targetAccounts, accountId, setAccountId, kind === "income" ? "Revenue category" : "Expense category")}
      {selectAccounts(assets, assetId, setAssetId, kind === "income" ? "Receiving cash/bank account" : "Paying cash/bank account")}
    </>}
    {error && <p role="alert" className="text-sm text-red-600 md:col-span-2">{error}</p>}
    <div className="md:col-span-2"><Button type="submit" disabled={pending || accounts.length === 0}>{pending ? "Saving draft…" : "Save accounting draft"}</Button><p className="mt-2 text-xs text-slate-500">This creates an unposted journal draft. Continue to its review page to submit, approve, and post according to your organization’s controls.</p></div>
  </form>;
}
