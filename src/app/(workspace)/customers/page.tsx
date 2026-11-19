import Link from "next/link";
import {getWorkspace} from "@/lib/data";
import {Card,PageHeader,EmptyState} from "@/components/ui";
import {DataTable} from "@/components/data-table";
import {PartyForm} from "@/components/receivables-payables-workspace";

export const metadata={title:"Customers"};
export default async function CustomersPage(){
 const {org,supabase}=await getWorkspace();if(!org||!supabase)return null;
 const {data,error}=await supabase.from("financial_parties").select("id,name,email,phone,is_active,created_at").eq("org_id",org.id).eq("party_type","customer").order("name");
 const canManage=["owner","administrator","accountant","finance_manager"].includes(org.role);
 return <><PageHeader eyebrow={org.name} title="Customers" description="Customer records used for receivables and sales invoices." action={canManage?<PartyForm orgId={org.id} type="customer"/>:null}/><Card className="p-4 md:p-5">{error?<EmptyState title="Customers unavailable" description={error.message}/>:<DataTable rows={(data??[]).map(p=>({...p,status:p.is_active?"Active":"Inactive"}))} columns={[{key:"name",label:"Customer",render:r=><Link className="font-semibold text-blue-700 underline" href={`/customers/${String(r.id)}`}>{String(r.name)}</Link>},{key:"email",label:"Email"},{key:"phone",label:"Phone"},{key:"created_at",label:"Added"},{key:"status",label:"Status"}]} empty="No customers recorded."/>}</Card><p className="mt-3 text-xs text-slate-500">Open a customer record to review its invoices, posted payments, and outstanding balance.</p></>;
}
