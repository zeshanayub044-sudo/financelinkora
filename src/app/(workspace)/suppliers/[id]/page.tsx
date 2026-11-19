import {notFound} from "next/navigation";
import Link from "next/link";
import {getWorkspace} from "@/lib/data";
import {Card,EmptyState,PageHeader} from "@/components/ui";
import {PartyContactCard,PartyHistory,PartyPaymentHistory} from "@/components/party-history";

export const metadata={title:"Supplier history"};
export default async function SupplierDetailPage({params}:{params:Promise<{id:string}>}){
 const {id}=await params;const {org,supabase}=await getWorkspace();if(!org||!supabase)return null;
 const [{data:party,error:partyError},{data:documents,error:documentsError}]=await Promise.all([
  supabase.from("financial_parties").select("id,name,email,phone,is_active,created_at").eq("org_id",org.id).eq("party_type","supplier").eq("id",id).maybeSingle(),
  supabase.from("financial_documents_exact").select("id,document_type,document_number,issue_date,due_date,journal_status,journal_entry_id,total,paid,outstanding,collection_status").eq("org_id",org.id).eq("party_id",id).eq("document_type","bill").order("issue_date",{ascending:false}),
 ]);
 if(partyError||!party)notFound();
 const documentIds=(documents??[]).map(d=>d.id);let paymentError:string|undefined;let paymentRows:{id:string;document_id:string;payment_date:string;account_id:string;amount:string;reference:string|null;journal_entry_id:string|null}[]=[];
 if(!documentsError&&documentIds.length){
  const result=await supabase.from("financial_document_payments").select("id,document_id,payment_date,account_id,amount,reference,journal_entry_id").eq("org_id",org.id).in("document_id",documentIds).order("payment_date",{ascending:false});
  paymentError=result.error?.message;paymentRows=result.data??[];
 }
 const accountIds=[...new Set(paymentRows.map(p=>p.account_id))],journalIds=[...new Set(paymentRows.flatMap(p=>p.journal_entry_id?[p.journal_entry_id]:[]))];
 const [{data:accounts,error:accountError},{data:journals,error:journalError}]=await Promise.all([
  accountIds.length?supabase.from("accounts").select("id,code,name").eq("org_id",org.id).in("id",accountIds):Promise.resolve({data:[],error:null}),
  journalIds.length?supabase.from("journal_entries").select("id,status").eq("org_id",org.id).in("id",journalIds):Promise.resolve({data:[],error:null}),
 ]);
 paymentError=paymentError||accountError?.message||journalError?.message;
 const docsById=new Map((documents??[]).map(d=>[d.id,d.document_number]));const accountsById=new Map((accounts??[]).map(a=>[a.id,`${a.code} · ${a.name}`]));const journalsById=new Map((journals??[]).map(j=>[j.id,j.status]));
 const payments=paymentRows.map(p=>({id:p.id,payment_date:p.payment_date,document_number:docsById.get(p.document_id)??"Document",amount:p.amount,reference:p.reference,account_label:accountsById.get(p.account_id)??"Account unavailable",journal_entry_id:p.journal_entry_id,journal_status:p.journal_entry_id?journalsById.get(p.journal_entry_id)??"Journal unavailable":"Journal unavailable"}));
 return <><PageHeader eyebrow="Supplier" title={party.name} description="Contact information, bills, payments, and payable history." action={<Link className="text-sm font-semibold text-blue-700 underline" href="/suppliers">Back to suppliers</Link>}/><PartyContactCard email={party.email} phone={party.phone} active={party.is_active} createdAt={party.created_at.slice(0,10)}/>{documentsError?<Card><EmptyState title="Bill history unavailable" description={documentsError.message}/></Card>:<><PartyHistory documents={(documents??[]) as never[]} currency={org.base_currency} documentLabel="Bills"/>{paymentError?<Card className="mt-5"><EmptyState title="Payment history unavailable" description={paymentError}/></Card>:<PartyPaymentHistory payments={payments} currency={org.base_currency}/>}</>}</>;
}
