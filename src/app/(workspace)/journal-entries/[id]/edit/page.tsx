import Link from "next/link";
import {notFound,redirect} from "next/navigation";
import {getWorkspace} from "@/lib/data";
import {Card,EmptyState,PageHeader} from "@/components/ui";
import {JournalForm} from "@/components/journal-form";

export const metadata={title:"Edit journal draft"};
export default async function EditJournalDraft({params}:{params:Promise<{id:string}>}){
  const {id}=await params;const {org,supabase,user}=await getWorkspace();
  if(!org||!supabase||!user)return null;
  const {data:entry,error}=await supabase.from("journal_entries")
    .select("id,entry_date,reference,description,currency,status,created_by,rejection_reason,entry_kind")
    .eq("id",id).eq("org_id",org.id).maybeSingle();
  if(error||!entry)notFound();
  if(entry.status!=="draft"||entry.created_by!==user.id)redirect(`/journal-entries/${id}`);
  const [{data:lines,error:lineError},{data:accounts,error:accountsError},{data:exchange,error:exchangeError},{data:departments,error:departmentError},{data:projects,error:projectError}]=await Promise.all([
    supabase.rpc("journal_entry_lines_with_dimensions_exact",{p_entry:id}),
    supabase.from("accounts").select("id,code,name,type").eq("org_id",org.id).eq("is_active",true).order("code"),
    supabase.rpc("journal_exchange_rate_exact",{p_entry:id}),
    supabase.from("departments").select("id,code,name").eq("org_id",org.id).eq("is_active",true).order("code"),
    supabase.from("projects").select("id,code,name").eq("org_id",org.id).eq("is_active",true).order("code"),
  ]);
  return <>
    <Link href={`/journal-entries/${id}`} className="mb-4 inline-block text-xs font-medium text-blue-700">← Journal entry</Link>
    <PageHeader eyebrow={org.name} title="Edit journal draft" description="Make corrections before resubmitting the entry for review."/>
    <Card className="p-5 md:p-7">{lineError||accountsError||exchangeError||departmentError||projectError?<EmptyState title="Draft unavailable" description={lineError?.message??accountsError?.message??exchangeError?.message??departmentError?.message??projectError?.message??"Unable to load draft details."}/>:<JournalForm
      orgId={org.id}
      currency={org.base_currency}
      accounts={accounts??[]}
      departments={departments??[]}
      projects={projects??[]}
      entryId={entry.id}
      rejectionReason={entry.rejection_reason}
      initialValues={{entry_date:entry.entry_date,reference:entry.reference??"",description:entry.description,currency:exchange?.[0]?.currency??entry.currency,exchange_rate:exchange?.[0]?.exchange_rate??"1",entry_kind:entry.entry_kind as "general"|"opening_balance"|"income"|"expense"|"bank_transfer"|"payment"|"closing"|"reversal",lines:lines??[]}}
    />}</Card>
  </>;
}
