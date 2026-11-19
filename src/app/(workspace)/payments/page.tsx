import {getWorkspace} from "@/lib/data";import {Card,PageHeader,EmptyState} from "@/components/ui";import {DocumentTable,PaymentHistoryTable,type PaymentRow} from "@/components/receivables-payables-workspace";
export const metadata={title:"Customer & supplier payments"};
export default async function PaymentsPage(){
 const {org,supabase,user}=await getWorkspace();if(!org||!supabase)return null;
 const [{data:accounts,error:accountError},{data:docs,error:docError},{data:payments,error:paymentError}]=await Promise.all([
  supabase.from("accounts").select("id,code,name,type,reporting_class").eq("org_id",org.id).eq("is_active",true).order("code"),
  supabase.from("financial_documents_exact").select("id,document_type,document_number,party_name,party_id,control_account_id,issue_date,due_date,journal_status,total,paid,outstanding,collection_status,created_by").eq("org_id",org.id).eq("journal_status","issued").order("due_date"),
  supabase.from("financial_document_payments").select("id,document_id,payment_date,account_id,amount,reference,journal_entry_id,created_by").eq("org_id",org.id).order("created_at",{ascending:false}).limit(200),
 ]);const failed=accountError||docError||paymentError;
 let paymentRows:PaymentRow[]=[];let historyError:string|null=null;
 if(!failed&&payments?.length){const journalIds=payments.flatMap(p=>p.journal_entry_id?[p.journal_entry_id]:[]);const documentIds=[...new Set(payments.map(p=>p.document_id))];const [{data:journalEntries,error:journalError},{data:documents,error:documentsError}]=await Promise.all([
   journalIds.length?supabase.from("journal_entries").select("id,status,rejection_reason").eq("org_id",org.id).in("id",journalIds):Promise.resolve({data:[],error:null}),
   supabase.from("financial_documents").select("id,document_type,document_number").eq("org_id",org.id).in("id",documentIds),
  ]);historyError=journalError?.message??documentsError?.message??null;
  const journalLookup=new Map((journalEntries??[]).map(e=>[e.id,e]));const documentLookup=new Map((documents??[]).map(d=>[d.id,d]));
  paymentRows=payments.flatMap(p=>{const document=documentLookup.get(p.document_id);if(!document)return[];const journal=p.journal_entry_id?journalLookup.get(p.journal_entry_id):null;return[{...p,document_number:document.document_number,document_type:document.document_type,journal_status:journal?.status??null,rejection_reason:journal?.rejection_reason??null}]}) as PaymentRow[];
 }
 return <><PageHeader eyebrow={org.name} title="Payments" description="Record customer receipts and supplier payments against posted invoices and bills."/><Card className="p-4 md:p-5">{failed?<EmptyState title="Payments unavailable" description={failed.message}/>:<DocumentTable currentUserId={user?.id??""} documents={(docs??[]) as never[]} accounts={(accounts??[]) as never[]} currency={org.base_currency}/>}</Card><Card className="mt-6 p-4 md:p-5"><h2 className="mb-3 font-semibold">Payment history and rejected drafts</h2>{failed||historyError?<EmptyState title="Payment history unavailable" description={failed?.message??historyError??"Unable to load payment history."}/>:<PaymentHistoryTable payments={paymentRows} accounts={(accounts??[]) as never[]} currency={org.base_currency} currentUserId={user?.id??""}/>}</Card><p className="mt-3 text-xs text-slate-500">Payments reserve part of an issued document balance and create journal drafts that require maker-checker approval before affecting balances. Rejected payments can be corrected and resubmitted by their creator while preserving the reservation and audit trail.</p></>;
}
