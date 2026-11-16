import Link from "next/link";
import { getWorkspace } from "@/lib/data";
import { Card, PageHeader, EmptyState } from "@/components/ui";
import { EntryActions } from "@/components/entry-actions";

export const metadata={title:"Approvals"};
export default async function ApprovalsPage(){
  const {org,supabase,user}=await getWorkspace();if(!org||!supabase)return null;
  const {data,error}=await supabase.from("journal_entries").select("id,entry_no,entry_date,description,status,created_by,approved_by,rejection_reason").eq("org_id",org.id).in("status",["draft","submitted","pending_approval","approved"]).order("created_at",{ascending:true});
  return <>
    <PageHeader eyebrow={org.name} title="Transaction approvals" description="Submit drafts, review entries, and post approved transactions through database-enforced maker-checker controls."/>
    <Card className="mb-5 border-blue-200 bg-blue-50/70 p-4 text-sm leading-6 text-blue-950"><strong>Workflow:</strong> The creator submits a balanced draft. A different authorized member queues it for review, approves or rejects it, and an authorized posting role posts approved entries. Rejection requires a reason and returns the entry to draft.</Card>
    {error?<Card><EmptyState title="Approval queue unavailable" description={error.message}/></Card>:data?.length?<div className="space-y-3">{data.map(e=><Card key={e.id} className="flex flex-col justify-between gap-4 p-5 sm:flex-row sm:items-center"><div className="min-w-0"><div className="flex flex-wrap items-center gap-2"><span className="text-xs font-bold text-slate-500">{e.entry_no??"Unnumbered draft"}</span><span className={`rounded-full px-2 py-1 text-[10px] font-semibold capitalize ${e.status==="approved"?"bg-green-50 text-green-700":e.status==="pending_approval"?"bg-amber-50 text-amber-700":"bg-slate-100 text-slate-700"}`}>{e.status.replaceAll("_"," ")}</span></div><Link href={`/journal-entries/${e.id}`} className="mt-1 block truncate font-semibold hover:text-blue-700">{e.description}</Link><p className="mt-1 text-xs text-slate-400">{e.entry_date} · Created by {e.created_by===user?.id?"you":e.created_by.slice(0,8)}{e.approved_by?` · Approved by ${e.approved_by.slice(0,8)}`:""}</p>{e.rejection_reason&&<p className="mt-2 rounded-md bg-red-50 p-2 text-xs text-red-700">Returned for correction: {e.rejection_reason}</p>}</div><EntryActions id={e.id} status={e.status} role={org.role} createdBy={e.created_by} currentUserId={user?.id}/></Card>)}</div>:<Card><EmptyState title="No entries in the review workflow" description="Drafts, submissions, approvals, and approved entries will appear here for authorized members."/></Card>}
  </>;
}

