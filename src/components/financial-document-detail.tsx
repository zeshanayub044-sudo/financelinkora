import {notFound} from "next/navigation";
import Link from "next/link";
import {getWorkspace} from "@/lib/data";
import {formatMoney,sumDecimals} from "@/lib/utils";
import {Card,EmptyState,PageHeader} from "@/components/ui";
import {DataTable} from "@/components/data-table";

export async function FinancialDocumentDetail({id,type}:{id:string;type:"invoice"|"bill"}){
 const {org,supabase,user}=await getWorkspace();if(!org||!supabase||!user)return null;
 const {data:document,error}=await supabase.from("financial_documents_exact").select("id,document_type,document_number,party_id,party_name,control_account_id,issue_date,due_date,journal_status,journal_entry_id,created_by,total,paid,outstanding,collection_status").eq("org_id",org.id).eq("id",id).eq("document_type",type).maybeSingle();
 if(error)return <><PageHeader eyebrow={type==="invoice"?"Sales invoice":"Supplier bill"} title="Document unavailable"/><Card><EmptyState title="Could not load this document" description={error.message}/></Card></>;
 if(!document)notFound();
 const [{data:lines,error:linesError},{data:payments,error:paymentsError}]=await Promise.all([
  supabase.from("financial_document_lines").select("id,account_id,description,amount,tax_rate,tax_amount,tax_account_id").eq("org_id",org.id).eq("document_id",id).order("created_at"),
  supabase.from("financial_document_payments").select("id,payment_date,account_id,amount,reference,journal_entry_id").eq("org_id",org.id).eq("document_id",id).order("payment_date",{ascending:false}),
 ]);
 const accountIds=[...new Set([document.control_account_id,...(lines??[]).flatMap(l=>[l.account_id,...(l.tax_account_id?[l.tax_account_id]:[])]),...(payments??[]).map(p=>p.account_id)])];
 const journalIds=[...new Set([...(document.journal_entry_id?[document.journal_entry_id]:[]),...(payments??[]).flatMap(p=>p.journal_entry_id?[p.journal_entry_id]:[])])];
 const [{data:accounts,error:accountError},{data:journals,error:journalError}]=await Promise.all([
  supabase.from("accounts").select("id,code,name").eq("org_id",org.id).in("id",accountIds),
  journalIds.length?supabase.from("journal_entries").select("id,entry_no,status").eq("org_id",org.id).in("id",journalIds):Promise.resolve({data:[],error:null}),
 ]);
 const accountsById=new Map((accounts??[]).map(a=>[a.id,`${a.code} · ${a.name}`]));
 const journalsById=new Map((journals??[]).map(j=>[j.id,j]));
 const linesView=(lines??[]).map(l=>({...l,account_label:accountsById.get(l.account_id)??"Account unavailable",tax_account_label:l.tax_account_id?accountsById.get(l.tax_account_id)??"Account unavailable":"—",gross:sumDecimals([l.amount,l.tax_amount])}));
 const paymentsView=(payments??[]).map(p=>({...p,account_label:accountsById.get(p.account_id)??"Account unavailable",journal_status:p.journal_entry_id?journalsById.get(p.journal_entry_id)?.status??"Journal unavailable":"Journal unavailable",entry_no:p.journal_entry_id?journalsById.get(p.journal_entry_id)?.entry_no??null:null}));
 const canEdit=document.journal_status==="draft"&&document.created_by===user.id;
 const editHref=type==="invoice"?`/invoices/${id}/edit`:`/suppliers/bills/${id}/edit`;
 const title=type==="invoice"?"Sales invoice":"Supplier bill";
 const errorMessage=linesError?.message||paymentsError?.message||accountError?.message||journalError?.message;
 return <>
  <PageHeader eyebrow={document.party_name} title={`${title} ${document.document_number}`} description={`${document.issue_date} · Due ${document.due_date}`} action={<div className="flex items-center gap-4"><Link className="text-sm font-semibold text-blue-700 underline" href={type==="invoice"?"/invoices":"/suppliers"}>Back</Link>{canEdit&&<Link className="text-sm font-semibold text-blue-700 underline" href={editHref}>Edit draft</Link>}</div>}/>
  <div className="mb-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
   {[{label:"Workflow",value:document.journal_status.replaceAll("_"," ")},{label:"Gross total",value:formatMoney(document.total,org.base_currency)},{label:"Paid",value:formatMoney(document.paid,org.base_currency)},{label:"Outstanding",value:formatMoney(document.outstanding,org.base_currency)}].map(x=><Card className="p-4" key={x.label}><p className="text-xs text-slate-500">{x.label}</p><p className="mt-1 text-lg font-semibold capitalize tabular-nums">{x.value}</p></Card>)}
  </div>
  {document.journal_entry_id&&<Card className="mb-5 flex flex-wrap items-center justify-between gap-3 p-4"><div><p className="text-xs text-slate-500">Accounting journal</p><p className="text-sm font-semibold">{journalsById.get(document.journal_entry_id)?.entry_no??"Journal entry"} · {journalsById.get(document.journal_entry_id)?.status??document.journal_status}</p></div><Link className="text-sm font-semibold text-blue-700 underline" href={`/journal-entries/${document.journal_entry_id}`}>Open journal</Link></Card>}
  {errorMessage?<Card><EmptyState title="Some document details are unavailable" description={errorMessage}/></Card>:<>
   <Card className="mb-5 p-4 md:p-5"><h2 className="mb-3 text-sm font-semibold">Document lines</h2><DataTable rows={linesView as unknown as Record<string,unknown>[]} columns={[
    {key:"description",label:"Description"},{key:"account_label",label:"Account"},
    {key:"amount",label:"Net",render:r=><span className="tabular-nums">{formatMoney(String(r.amount),org.base_currency)}</span>},
    {key:"tax_rate",label:"Tax rate",render:r=><span>{String(r.tax_rate)!=="0"&&String(r.tax_rate)!=="0.0000"?`${r.tax_rate}%`:"—"}</span>},
    {key:"tax_account_label",label:"Tax account"},
    {key:"gross",label:"Gross",render:r=><span className="tabular-nums">{formatMoney(String(r.gross),org.base_currency)}</span>},
   ]} empty="This document has no line items."/></Card>
   <Card className="p-4 md:p-5"><h2 className="mb-3 text-sm font-semibold">Payment history</h2><DataTable rows={paymentsView as unknown as Record<string,unknown>[]} columns={[
    {key:"payment_date",label:"Date"},{key:"reference",label:"Reference"},{key:"account_label",label:"Account"},
    {key:"amount",label:"Amount",render:r=><span className="tabular-nums">{formatMoney(String(r.amount),org.base_currency)}</span>},
    {key:"journal_status",label:"Journal status",render:r=><span className="capitalize">{String(r.journal_status)}</span>},
    {key:"journal_entry_id",label:"Journal",render:r=>r.journal_entry_id?<Link className="font-semibold text-blue-700 underline" href={`/journal-entries/${String(r.journal_entry_id)}`}>{String(r.entry_no??"View entry")}</Link>:<span className="text-slate-400">Not created</span>},
   ]} empty="No payments have been recorded."/></Card>
  </>}
 </>;
}
