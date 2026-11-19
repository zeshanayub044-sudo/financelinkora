import Link from "next/link";
import {Card} from "@/components/ui";
import {DataTable} from "@/components/data-table";
import {formatMoney,sumDecimals} from "@/lib/utils";

export type PartyDocument={id:string;document_type:"invoice"|"bill";document_number:string;issue_date:string;due_date:string;journal_status:string;journal_entry_id:string|null;total:string;paid:string;outstanding:string;collection_status:string};
export type PartyPayment={id:string;payment_date:string;document_number:string;amount:string;reference:string|null;account_label:string;journal_entry_id:string|null;journal_status:string|null};

export function PartyHistory({documents,currency,documentLabel}:{documents:PartyDocument[];currency:string;documentLabel:string}){
 const issued=documents.filter(d=>d.journal_status==="issued");
 const collected=sumDecimals(issued.map(d=>d.paid));
 const outstanding=sumDecimals(issued.map(d=>d.outstanding));
 const rows=documents.map(d=>({...d,status:d.collection_status.replaceAll("_"," ")}));
 return <>
  <div className="mb-5 grid gap-3 sm:grid-cols-3">
   <Card className="p-4"><p className="text-xs text-slate-500">{documentLabel}</p><p className="mt-1 text-xl font-semibold tabular-nums">{documents.length}</p></Card>
   <Card className="p-4"><p className="text-xs text-slate-500">Collected / paid on issued {documentLabel.toLowerCase()}</p><p className="mt-1 text-xl font-semibold tabular-nums">{formatMoney(collected,currency)}</p></Card>
   <Card className="p-4"><p className="text-xs text-slate-500">Outstanding on issued {documentLabel.toLowerCase()}</p><p className="mt-1 text-xl font-semibold tabular-nums">{formatMoney(outstanding,currency)}</p></Card>
  </div>
  <Card className="p-4 md:p-5">
   {<DataTable rows={rows as unknown as Record<string,unknown>[]} columns={[
    {key:"document_number",label:"Document",render:r=><span className="font-semibold">{String(r.document_number)}</span>},
    {key:"issue_date",label:"Issued"},{key:"due_date",label:"Due"},
    {key:"status",label:"Status",render:r=><span className="capitalize">{String(r.status)}</span>},
    {key:"total",label:"Total",render:r=><span className="tabular-nums">{formatMoney(String(r.total),currency)}</span>},
    {key:"paid",label:"Paid",render:r=><span className="tabular-nums">{formatMoney(String(r.paid),currency)}</span>},
    {key:"outstanding",label:"Outstanding",render:r=><span className="tabular-nums">{formatMoney(String(r.outstanding),currency)}</span>},
    {key:"journal_entry_id",label:"Journal",render:r=>r.journal_entry_id?<Link className="font-semibold text-blue-700 underline" href={`/journal-entries/${String(r.journal_entry_id)}`}>View entry</Link>:<span className="text-slate-400">Not posted</span>},
   ]} empty={`No ${documentLabel.toLowerCase()} are recorded for this party.`}/>}
   <p className="mt-3 text-xs text-slate-500">Amounts use the organization’s base currency. Collected and outstanding totals include issued documents only; drafts and void documents remain visible in the history.</p>
  </Card>
 </>;
}

export function PartyPaymentHistory({payments,currency}:{payments:PartyPayment[];currency:string}){
 const rows=payments.map(p=>({...p,workflow:p.journal_status?.replaceAll("_"," ")??"Journal unavailable"}));
 return <Card className="mt-5 p-4 md:p-5"><h2 className="mb-3 text-sm font-semibold">Payment history</h2><DataTable rows={rows as unknown as Record<string,unknown>[]} columns={[
  {key:"payment_date",label:"Payment date"},{key:"document_number",label:"Document"},
  {key:"reference",label:"Reference"},{key:"account_label",label:"Receiving / payment account"},
  {key:"amount",label:"Amount",render:r=><span className="tabular-nums">{formatMoney(String(r.amount),currency)}</span>},
  {key:"workflow",label:"Journal status",render:r=><span className="capitalize">{String(r.workflow)}</span>},
  {key:"journal_entry_id",label:"Journal",render:r=>r.journal_entry_id?<Link className="font-semibold text-blue-700 underline" href={`/journal-entries/${String(r.journal_entry_id)}`}>View entry</Link>:<span className="text-slate-400">Not created</span>},
 ]} empty="No payments have been recorded for this party."/></Card>;
}

export function PartyContactCard({email,phone,active,createdAt}:{email:string|null;phone:string|null;active:boolean;createdAt:string}){
 return <Card className="mb-5 grid gap-4 p-4 sm:grid-cols-3">
  <div><p className="text-[10px] font-semibold uppercase tracking-wide text-slate-500">Email</p><p className="mt-1 text-sm">{email||"Not provided"}</p></div>
  <div><p className="text-[10px] font-semibold uppercase tracking-wide text-slate-500">Phone</p><p className="mt-1 text-sm">{phone||"Not provided"}</p></div>
  <div><p className="text-[10px] font-semibold uppercase tracking-wide text-slate-500">Record</p><p className="mt-1 text-sm">{active?"Active":"Inactive"} · added {createdAt}</p></div>
 </Card>;
}
