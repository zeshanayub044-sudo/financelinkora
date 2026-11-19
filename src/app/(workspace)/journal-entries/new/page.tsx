import Link from "next/link";
import {getWorkspace} from "@/lib/data";
import {Card,EmptyState,PageHeader} from "@/components/ui";
import {JournalForm} from "@/components/journal-form";

export const metadata={title:"New journal entry"};
export default async function NewEntry(){
 const {org,supabase}=await getWorkspace();if(!org||!supabase)return null;
 const [{data:accounts,error:accountError},{data:departments,error:departmentError},{data:projects,error:projectError}]=await Promise.all([
  supabase.from("accounts").select("id,code,name,type").eq("org_id",org.id).eq("is_active",true).order("code"),
  supabase.from("departments").select("id,code,name").eq("org_id",org.id).eq("is_active",true).order("code"),
  supabase.from("projects").select("id,code,name").eq("org_id",org.id).eq("is_active",true).order("code"),
 ]);
 const error=accountError??departmentError??projectError;const allowOpeningBalance=["owner","finance_manager"].includes(org.role);
 return <><Link href="/journal-entries" className="mb-4 inline-block text-xs font-medium text-blue-700">← Journal entries</Link>
  <PageHeader eyebrow={org.name} title="New journal entry" description="Enter balanced debits and credits. Optionally allocate each line to a department and project."/>
  <Card className="p-5 md:p-7">{error?<EmptyState title="Journal form unavailable" description={error.message}/>:accounts?.length?<JournalForm orgId={org.id} currency={org.base_currency} accounts={accounts} departments={departments??[]} projects={projects??[]} allowOpeningBalance={allowOpeningBalance}/>:<EmptyState title="Chart of accounts is empty" description="An organization created through the setup function receives a starter chart of accounts. Add accounts before recording entries."/>}</Card>
 </>;
}
