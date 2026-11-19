import Link from "next/link";
import {z} from "zod";
import {getWorkspace} from "@/lib/data";
import {BusinessEntryForm} from "@/components/business-entry-form";
import {BusinessEntryFilters} from "@/components/business-entry-filters";
import {Card,EmptyState,PageHeader} from "@/components/ui";
import {DataTable} from "@/components/data-table";
import {RecurringTransactionsWorkspace} from "@/components/recurring-transactions-workspace";
import {formatMoney} from "@/lib/utils";
import {buildBusinessEntryHistoryRows,filterEntriesByCategory} from "@/lib/business-entry-history";

export const metadata={title:"Expenses"};
export default async function ExpensesPage({searchParams}:{searchParams:Promise<{from?:string;to?:string;category?:string}>}){
 const {org,supabase}=await getWorkspace();if(!org||!supabase)return null;
 const params=await searchParams;const fromParsed=params.from?z.iso.date().safeParse(params.from):null;const toParsed=params.to?z.iso.date().safeParse(params.to):null;
 const from=fromParsed?.success?fromParsed.data:"",to=toParsed?.success?toParsed.data:"";
 const rangeError=(params.from&&!from)||(params.to&&!to)||(from&&to&&from>to)?"Choose a valid date range.":null;
 const entryRequestBase=supabase.from("journal_entries").select("id,entry_no,entry_date,description,reference,status,created_at").eq("org_id",org.id).eq("entry_kind","expense").order("entry_date",{ascending:false});
 const entryRequest=from?entryRequestBase.gte("entry_date",from):entryRequestBase;
 const filteredEntryRequest=to?entryRequest.lte("entry_date",to):entryRequest;
 const [{data:accounts,error:accountsError},{data:entries,error},{data:templates,error:templateError},{data:occurrences,error:occurrenceError}]=await Promise.all([
  supabase.from("accounts").select("id,code,name,type,reporting_class,is_active").eq("org_id",org.id).order("code"),
  filteredEntryRequest,
  supabase.from("recurring_templates").select("id,name,transaction_kind,frequency,start_date,end_date,next_date,amount,category_account_id,asset_account_id,description,reference_prefix,is_active").eq("org_id",org.id).eq("transaction_kind","expense").order("created_at",{ascending:false}),
  supabase.from("recurring_occurrences").select("template_id,scheduled_date,journal_entry_id").eq("org_id",org.id).order("scheduled_date",{ascending:false}).limit(50),
 ]);
 const categories=(accounts??[]).filter(a=>a.type==="expense");
 const selected=params.category?categories.find(a=>a.id===params.category):undefined;
 let filterError=rangeError??(!selected&&params.category?"Choose a valid expense category.":null);
 let lines:{entry_id:string;account_id:string}[]=[];
 if(entries?.length){const result=await supabase.from("journal_lines").select("entry_id,account_id").eq("org_id",org.id).in("entry_id",entries.map(e=>e.id));filterError=filterError||result.error?.message||null;lines=result.data??[];}
 const postedIds=(entries??[]).filter(e=>e.status==="posted"||e.status==="reversed").map(e=>e.id);
 const {data:ledger,error:ledgerError}=postedIds.length?await supabase.from("ledger_exact").select("entry_id,account_id,debit,credit").eq("org_id",org.id).in("entry_id",postedIds):{data:[],error:null};
 filterError=filterError||ledgerError?.message||null;
 const visibleEntries=selected?filterEntriesByCategory(entries??[],lines,selected.id):(entries??[]);
 const rows=buildBusinessEntryHistoryRows(visibleEntries,lines,ledger??[],accounts??[],"expense");
 const canCreate=["owner","administrator","accountant","finance_manager"].includes(org.role);
 const {data:occurrenceEntries,error:occurrenceEntryError}=occurrences?.length?await supabase.from("journal_entries").select("id,entry_no,status").eq("org_id",org.id).in("id",occurrences.map(o=>o.journal_entry_id)):{data:[],error:null};
 const entryLookup=new Map((occurrenceEntries??[]).map(e=>[e.id,e]));
 const occurrenceRows=(occurrences??[]).flatMap(o=>{const e=entryLookup.get(o.journal_entry_id);return e?[{...o,entry_no:e.entry_no,status:e.status}]:[];});
 const historyError=error?.message||accountsError?.message||filterError;
 const columns=[{key:"entry_no",label:"Entry",render:(r:Record<string,unknown>)=><Link className="font-semibold text-blue-700 hover:underline" href={`/journal-entries/${r.id}`}>{String(r.entry_no)}</Link>},{key:"entry_date",label:"Date"},{key:"description",label:"Description"},{key:"category",label:"Category"},{key:"amount",label:"Posted amount",render:(r:Record<string,unknown>)=>r.amount==="—"?"Not posted":formatMoney(String(r.amount),org.base_currency)},{key:"reference",label:"Reference"},{key:"status",label:"Workflow",render:(r:Record<string,unknown>)=><span className="capitalize">{String(r.status).replaceAll("_"," ")}</span>}];
 return <><PageHeader eyebrow={org.name} title="Expenses" description="Record expenses against a category and cash or bank account."/>
  {canCreate&&<Card className="mb-6 p-5"><h2 className="mb-4 font-semibold">Record expense</h2>{accountsError?<EmptyState title="Accounts unavailable" description={accountsError.message}/>:<BusinessEntryForm orgId={org.id} kind="expense" accounts={(accounts??[]).filter(a=>a.is_active)}/>}</Card>}
  <Card className="p-4 md:p-5"><h2 className="mb-4 text-sm font-semibold">Expense history</h2><BusinessEntryFilters action="/expenses" from={from} to={to} category={selected?.id??""} categories={categories}/>{historyError?<EmptyState title="Expense entries unavailable" description={historyError}/>:<DataTable rows={rows as unknown as Record<string,unknown>[]} columns={columns} empty="No expense drafts or posted expenses match these filters."/>}</Card>
  {(templateError||occurrenceError||occurrenceEntryError)?<Card className="mt-6 p-4 text-sm text-amber-800">Recurring schedules are unavailable until migration 021 is applied: {(templateError??occurrenceError??occurrenceEntryError)?.message}</Card>:<RecurringTransactionsWorkspace orgId={org.id} kind="expense" currency={org.base_currency} accounts={(accounts??[]) as {id:string;code:string;name:string;type:string;reporting_class:string|null;is_active:boolean}[]} templates={(templates??[]) as never} occurrences={occurrenceRows as never} canManage={canCreate}/>}
  <p className="mt-3 text-xs text-slate-500">Expense entries and recurring schedules create drafts only. Vendor bills, payables, partial payments, and receipt uploads are available in their respective workflows. Date and category filters apply to organization-scoped journal records.</p>
 </>;
}
