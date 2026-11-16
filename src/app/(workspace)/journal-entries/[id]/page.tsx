import Link from "next/link";
import { notFound } from "next/navigation";
import { getWorkspace } from "@/lib/data";
import { PageHeader, Card } from "@/components/ui";
import { EntryActions } from "@/components/entry-actions";
import { formatMoney } from "@/lib/utils";

export default async function EntryDetail({params}:{params:Promise<{id:string}>}){
  const {id}=await params;const {org,supabase,user}=await getWorkspace();if(!org||!supabase)return null;
  const [{data:entry,error},{data:lines}]=await Promise.all([
    supabase.from("journal_entries").select("id,entry_no,entry_date,reference,description,currency,status,created_by,approved_by,posted_at,reverses_id,exchange_rate,rejection_reason,reversal_reason").eq("id",id).eq("org_id",org.id).maybeSingle(),
    supabase.from("journal_lines").select("id,account_id,debit,credit,memo").eq("entry_id",id),
  ]);
  if(error||!entry)notFound();
  const {data:accounts}=await supabase.from("accounts").select("id,code,name").eq("org_id",org.id);
  const lookup=new Map((accounts??[]).map(a=>[a.id,`${a.code} · ${a.name}`]));
  const debitTotal=(lines??[]).reduce((s,l)=>s+Number(l.debit),0);const creditTotal=(lines??[]).reduce((s,l)=>s+Number(l.credit),0);
  return <>
    <Link href="/journal-entries" className="mb-4 inline-block text-xs font-medium text-blue-700">← Journal entries</Link>
    <PageHeader eyebrow={entry.entry_no??"Draft entry"} title={entry.description} description={`${entry.entry_date} · ${entry.reference||"No reference"} · ${entry.currency}`} action={<EntryActions id={entry.id} status={entry.status} role={org.role} createdBy={entry.created_by} currentUserId={user?.id}/>}/>
    <div className="mb-5 grid gap-3 sm:grid-cols-3"><Card className="p-4"><p className="text-xs text-slate-500">Status</p><p className="mt-1 font-semibold capitalize">{entry.status.replaceAll("_"," ")}</p></Card><Card className="p-4"><p className="text-xs text-slate-500">Created by</p><p className="mt-1 truncate font-mono text-xs">{entry.created_by}</p></Card><Card className="p-4"><p className="text-xs text-slate-500">Approved by</p><p className="mt-1 truncate font-mono text-xs">{entry.approved_by??"Awaiting approval"}</p></Card></div>
    {entry.rejection_reason&&<Card className="mb-4 border-red-200 bg-red-50 p-4 text-sm text-red-800"><strong>Returned for correction:</strong> {entry.rejection_reason}</Card>}
    {entry.reversal_reason&&<Card className="mb-4 border-blue-200 bg-blue-50 p-4 text-sm text-blue-900"><strong>Reversal reason:</strong> {entry.reversal_reason}{entry.reverses_id&&<span> · Reverses entry {entry.reverses_id}</span>}</Card>}
    <Card className="overflow-x-auto"><table className="w-full min-w-[600px] text-left text-sm"><thead className="bg-slate-50 text-[10px] uppercase tracking-wide text-slate-500"><tr><th className="p-4">Account</th><th className="p-4">Memo</th><th className="p-4 text-right">Debit</th><th className="p-4 text-right">Credit</th></tr></thead><tbody>{(lines??[]).map(l=><tr className="border-t border-border" key={l.id}><td className="p-4">{lookup.get(l.account_id)??"Account"}</td><td className="p-4 text-slate-500">{l.memo??"—"}</td><td className="p-4 text-right tabular-nums">{Number(l.debit)?formatMoney(l.debit,entry.currency):"—"}</td><td className="p-4 text-right tabular-nums">{Number(l.credit)?formatMoney(l.credit,entry.currency):"—"}</td></tr>)}</tbody><tfoot className="border-t border-border bg-slate-50 font-semibold"><tr><td colSpan={2} className="p-4 text-right">Totals</td><td className="p-4 text-right">{formatMoney(debitTotal,entry.currency)}</td><td className="p-4 text-right">{formatMoney(creditTotal,entry.currency)}</td></tr></tfoot></table></Card>
  </>;
}

