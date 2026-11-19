import Link from "next/link";
import { notFound } from "next/navigation";
import { getWorkspace } from "@/lib/data";
import { PageHeader, Card } from "@/components/ui";
import { EntryActions } from "@/components/entry-actions";
import { formatMoney, isZeroDecimal, sumDecimals } from "@/lib/utils";
import {ReceiptAttachments} from "@/components/receipt-attachments";

export default async function EntryDetail({params}:{params:Promise<{id:string}>}){
  const {id}=await params;const {org,supabase,user}=await getWorkspace();if(!org||!supabase)return null;
  const [{data:entry,error},{data:lines},{data:exchange}]=await Promise.all([
    supabase.from("journal_entries").select("id,entry_no,entry_date,reference,description,currency,status,created_by,approved_by,posted_at,reverses_id,exchange_rate,rejection_reason,reversal_reason,entry_kind").eq("id",id).eq("org_id",org.id).maybeSingle(),
    supabase.rpc("journal_entry_lines_with_dimensions_exact",{p_entry:id}),
    supabase.rpc("journal_exchange_rate_exact",{p_entry:id}),
  ]);
  if(error||!entry)notFound();
  const receiptRoles=["owner","administrator","finance_manager","accountant","auditor","viewer"];
  const canReadReceipts=receiptRoles.includes(org.role);
  const receiptResult=canReadReceipts&&(entry.entry_kind==="income"||entry.entry_kind==="expense")
    ?await supabase.from("receipt_attachments").select("id,storage_path,original_name,mime_type,size_bytes,created_at").eq("org_id",org.id).eq("entry_id",entry.id).order("created_at")
    :{data:[],error:null};
  const {data:reversal}=entry.status==="reversed"
    ?await supabase.from("journal_entries").select("id,entry_no").eq("org_id",org.id).eq("reverses_id",entry.id).maybeSingle()
    :{data:null};
  const [{data:accounts},{data:departments},{data:projects}]=await Promise.all([
    supabase.from("accounts").select("id,code,name").eq("org_id",org.id),
    supabase.from("departments").select("id,code,name").eq("org_id",org.id),
    supabase.from("projects").select("id,code,name").eq("org_id",org.id),
  ]);
  const lookup=new Map((accounts??[]).map(a=>[a.id,`${a.code} · ${a.name}`]));
  const departmentLookup=new Map((departments??[]).map(d=>[d.id,`${d.code} · ${d.name}`]));
  const projectLookup=new Map((projects??[]).map(p=>[p.id,`${p.code} · ${p.name}`]));
  const transactionCurrency=exchange?.[0]?.currency??entry.currency;const exchangeRate=exchange?.[0]?.exchange_rate??String(entry.exchange_rate);
  const debitTotal=sumDecimals((lines??[]).map(l=>l.debit));const creditTotal=sumDecimals((lines??[]).map(l=>l.credit));
  return <>
    <Link href="/journal-entries" className="mb-4 inline-block text-xs font-medium text-blue-700">← Journal entries</Link>
    <PageHeader eyebrow={`${entry.entry_no??"Draft entry"} · ${entry.entry_kind.replaceAll("_"," ")}`} title={entry.description} description={`${entry.entry_date} · ${entry.reference||"No reference"} · ${transactionCurrency}`} action={<EntryActions id={entry.id} status={entry.status} role={org.role} createdBy={entry.created_by} currentUserId={user?.id} balanced={(lines??[]).length>=2&&debitTotal===creditTotal}/>}/>
    <div className="mb-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4"><Card className="p-4"><p className="text-xs text-slate-500">Status</p><p className="mt-1 font-semibold capitalize">{entry.status.replaceAll("_"," ")}</p></Card><Card className="p-4"><p className="text-xs text-slate-500">Created by</p><p className="mt-1 truncate font-mono text-xs">{entry.created_by}</p></Card><Card className="p-4"><p className="text-xs text-slate-500">Approved by</p><p className="mt-1 truncate font-mono text-xs">{entry.approved_by??"Awaiting approval"}</p></Card><Card className="p-4"><p className="text-xs text-slate-500">Manual exchange rate</p><p className="mt-1 font-mono text-sm">1 {transactionCurrency} = {exchangeRate} {org.base_currency}</p></Card></div>
    {entry.rejection_reason&&<Card className="mb-4 border-red-200 bg-red-50 p-4 text-sm text-red-800"><strong>Returned for correction:</strong> {entry.rejection_reason}</Card>}
    {entry.reversal_reason&&<Card className="mb-4 border-blue-200 bg-blue-50 p-4 text-sm text-blue-900"><strong>Reversal reason:</strong> {entry.reversal_reason}{entry.reverses_id&&<span> · Reverses entry {entry.reverses_id}</span>}</Card>}
    {reversal&&<Card className="mb-4 border-blue-200 bg-blue-50 p-4 text-sm text-blue-900"><strong>Reversed by:</strong> <Link className="font-semibold underline" href={`/journal-entries/${reversal.id}`}>{reversal.entry_no??reversal.id}</Link></Card>}
    <Card className="overflow-x-auto"><table className="w-full min-w-[900px] text-left text-sm"><thead className="bg-slate-50 text-[10px] uppercase tracking-wide text-slate-500"><tr><th className="p-4">Account</th><th className="p-4">Department</th><th className="p-4">Project</th><th className="p-4">Memo</th><th className="p-4 text-right">Debit</th><th className="p-4 text-right">Credit</th></tr></thead><tbody>{(lines??[]).map(l=><tr className="border-t border-border" key={l.id}><td className="p-4">{lookup.get(l.account_id)??"Account"}</td><td className="p-4">{l.department_id?departmentLookup.get(l.department_id)??"Department":"—"}</td><td className="p-4">{l.project_id?projectLookup.get(l.project_id)??"Project":"—"}</td><td className="p-4 text-slate-500">{l.memo??"—"}</td><td className="p-4 text-right tabular-nums">{isZeroDecimal(l.debit)?"—":formatMoney(l.debit,entry.currency)}</td><td className="p-4 text-right tabular-nums">{isZeroDecimal(l.credit)?"—":formatMoney(l.credit,entry.currency)}</td></tr>)}</tbody><tfoot className="border-t border-border bg-slate-50 font-semibold"><tr><td colSpan={4} className="p-4 text-right">Totals</td><td className="p-4 text-right">{formatMoney(debitTotal,entry.currency)}</td><td className="p-4 text-right">{formatMoney(creditTotal,entry.currency)}</td></tr></tfoot></table></Card>
    {canReadReceipts&&(entry.entry_kind==="income"||entry.entry_kind==="expense")&&<>{receiptResult.error?<Card className="mt-5 p-4 text-sm text-amber-800">Receipt storage is not configured yet. Apply migration 020 before uploading receipt files.</Card>:<ReceiptAttachments orgId={org.id} entryId={entry.id} items={(receiptResult.data??[]) as {id:string;storage_path:string;original_name:string;mime_type:string;size_bytes:number;created_at:string}[]} canUpload={["owner","administrator","finance_manager","accountant"].includes(org.role)}/>}</>}
  </>;
}
