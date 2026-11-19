import {notFound} from "next/navigation";
import {getWorkspace} from "@/lib/data";
import {Card,PageHeader} from "@/components/ui";
import {DocumentForm} from "@/components/receivables-payables-workspace";
export const metadata={title:"Edit bill draft"};
export default async function EditBillPage({params}:{params:Promise<{id:string}>}){
 const {id}=await params;const {org,supabase,user}=await getWorkspace();if(!org||!supabase||!user)return null;
 const [{data:doc},{data:lines},{data:parties},{data:accounts},{data:taxCodes}]=await Promise.all([
  supabase.from("financial_documents").select("id,document_type,document_number,party_id,control_account_id,issue_date,due_date,status,created_by").eq("org_id",org.id).eq("id",id).maybeSingle(),
  supabase.from("financial_document_lines").select("account_id,amount,description,tax_code_id").eq("org_id",org.id).eq("document_id",id).order("created_at"),
  supabase.from("financial_parties").select("id,name,party_type").eq("org_id",org.id).eq("party_type","supplier").eq("is_active",true).order("name"),
  supabase.from("accounts").select("id,code,name,type,reporting_class").eq("org_id",org.id).eq("is_active",true).order("code"),
  supabase.from("tax_codes").select("id,code,name,scope,rate,effective_from,effective_to,is_active").eq("org_id",org.id).order("code"),
 ]);
 if(!doc||doc.document_type!=="bill"||doc.status!=="draft"||doc.created_by!==user.id)notFound();
 return <><PageHeader eyebrow={org.name} title="Edit bill draft" description="Changes remain in draft until you submit the bill for review."/><Card className="p-4"><DocumentForm orgId={org.id} type="bill" currency={org.base_currency} taxCodes={(taxCodes??[]) as never[]} parties={(parties??[]) as {id:string;name:string;party_type:"customer"|"supplier"}[]} accounts={(accounts??[]) as never[]} initial={{id:doc.id,party_id:doc.party_id,document_number:doc.document_number,issue_date:doc.issue_date,due_date:doc.due_date,control_account_id:doc.control_account_id,lines:(lines??[]).map(l=>({account_id:l.account_id,amount:String(l.amount),description:l.description,tax_code_id:l.tax_code_id}))}}/></Card></>;
}
