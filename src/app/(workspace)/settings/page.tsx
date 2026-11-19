import {getWorkspace} from "@/lib/data";
import {MemberManagement} from "@/components/member-management";
import {Card,EmptyState,PageHeader} from "@/components/ui";

export const metadata={title:"Settings"};
export default async function SettingsPage(){
  const {org,supabase,user}=await getWorkspace();if(!org||!supabase)return null;
  const [{data,error},{data:members,error:membersError}]=await Promise.all([
    supabase.from("organizations").select("legal_name,country,city,base_currency,fy_start_month,accounting_method").eq("id",org.id).maybeSingle(),
    supabase.from("organization_members").select("user_id,role").eq("org_id",org.id).order("role"),
  ]);
  return <><PageHeader eyebrow={org.name} title="Settings" description="Organization profile, accounting configuration, member access, and account security."/>
    <div className="grid gap-5 xl:grid-cols-2">
      <Card className="p-5"><h2 className="font-semibold">Organization</h2>{error?<EmptyState title="Organization unavailable" description={error.message}/>:<><dl className="mt-4 divide-y divide-border text-sm">{[["Legal name",data?.legal_name??"Not set"],["Location",[data?.city,data?.country].filter(Boolean).join(", ")||"Not set"],["Base currency",data?.base_currency??org.base_currency],["Fiscal year start month",data?.fy_start_month??"—"],["Accounting method",data?.accounting_method??"—"]].map(([title,value])=><div className="flex justify-between gap-4 py-3" key={title}><dt className="text-slate-500">{title}</dt><dd className="text-right font-medium">{value}</dd></div>)}</dl><p className="mt-2 text-xs text-slate-400">Organization details are currently read-only. Ask the owner to configure them before recording transactions.</p></>}</Card>
      <Card className="p-5"><h2 className="font-semibold">Accounting controls</h2><p className="mt-2 text-sm leading-6 text-slate-500">Maker-checker approval is enforced for every journal posting. The entry creator cannot approve their own entry. Posted entries are immutable; corrections require an authorized reversal that also passes through approval.</p><h3 className="mt-8 font-semibold">Signed-in account</h3><p className="mt-2 text-sm text-slate-600">{user?.email}</p><p className="mt-1 text-xs text-slate-400">Sessions use Supabase Auth with cookie-based server rendering. Membership roles and row-level security control access to financial data.</p></Card>
    </div>
    <Card className="mt-5 p-5"><div className="mb-4"><h2 className="font-semibold">Organization members</h2><p className="mt-1 text-xs text-slate-500">Manage who can access this organization and which accounting operations their role permits.</p></div>{membersError?<EmptyState title="Membership list unavailable" description={membersError.message}/>:<MemberManagement orgId={org.id} currentRole={org.role} currentUserId={user?.id??""} members={(members??[]) as {user_id:string;role:"owner"|"administrator"|"finance_manager"|"accountant"|"approver"|"auditor"|"viewer"|"employee"}[]}/>}</Card>
  </>;
}
