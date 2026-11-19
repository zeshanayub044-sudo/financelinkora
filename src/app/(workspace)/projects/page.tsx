import Link from "next/link";
import {getWorkspace} from "@/lib/data";
import {Card,EmptyState,PageHeader} from "@/components/ui";
import {DataTable} from "@/components/data-table";
import {CsvExport} from "@/components/csv-export";
import {DateFilter} from "@/components/date-filter";
import {DimensionActiveControl,DimensionCreateForm,DimensionReportSelector} from "@/components/dimensions-workspace";
import {formatMoney,negateDecimal,sumDecimals} from "@/lib/utils";

export const metadata={title:"Projects"};
export default async function ProjectsPage({searchParams}:{searchParams:Promise<{from?:string;to?:string;project?:string}>}){
 const {org,supabase}=await getWorkspace();if(!org||!supabase)return null;const q=await searchParams;const today=new Date().toISOString().slice(0,10);const from=q.from??`${today.slice(0,4)}-01-01`;const to=q.to??today;
 const [{data:projects,error:projectError},{data:activity,error:activityError}]=await Promise.all([
  supabase.from("projects").select("id,org_id,code,name,description,is_active,start_date,end_date,created_at").eq("org_id",org.id).order("code"),
  q.project?supabase.rpc("dimension_activity_exact",{p_org:org.id,p_from:from,p_to:to,p_dimension_type:"project",p_dimension:q.project}):Promise.resolve({data:null,error:null}),
 ]);
 const selected=projects?.find(p=>p.id===q.project);const canManage=["owner","administrator","accountant","finance_manager"].includes(org.role);
 const revenues=sumDecimals((activity??[]).filter(r=>r.type==="revenue").map(r=>r.balance));const expenses=sumDecimals((activity??[]).filter(r=>r.type==="expense").map(r=>r.balance));const result=sumDecimals([revenues,negateDecimal(expenses)]);
 const reportRows=(activity??[]).map((r,i)=>({...r,id:`activity-${i}`,debit_display:formatMoney(r.debit,org.base_currency),credit_display:formatMoney(r.credit,org.base_currency),balance_display:formatMoney(r.balance,org.base_currency)}));
 const csvRows=(activity??[]).map(r=>[r.code,r.name,r.type,r.debit,r.credit,r.balance]);
 const projectRows=(projects??[]).map(p=>({...p,status:<DimensionActiveControl orgId={org.id} kind="project" id={p.id} isActive={p.is_active} canManage={canManage}/> }));
 const projectColumns=[{key:"code",label:"Code"},{key:"name",label:"Project"},{key:"start_date",label:"Start"},{key:"end_date",label:"End"},{key:"description",label:"Description"},{key:"status",label:"Status",render:(r:Record<string,unknown>)=>r.status as React.ReactNode}];
 return <>
  <PageHeader eyebrow={org.name} title="Projects" description="Maintain projects and review posted-ledger activity allocated to each one." action={<Link className="rounded-lg border border-border px-3 py-2 text-sm text-blue-700" href="/departments">Departments →</Link>}/>
  {canManage&&<Card className="mb-5 p-4 md:p-5"><h2 className="mb-3 font-semibold">Create project</h2><DimensionCreateForm orgId={org.id} kind="project"/></Card>}
  <Card className="mb-5 p-4 md:p-5"><h2 className="mb-3 font-semibold">Project register</h2>{projectError?<EmptyState title="Projects unavailable" description={projectError.message}/>:<DataTable rows={projectRows as unknown as Record<string,unknown>[]} columns={projectColumns} empty="No projects created yet."/>}</Card>
  <Card className="mb-5 p-4 md:p-5"><h2 className="mb-3 font-semibold">Posted activity and profitability</h2><div className="grid gap-3 md:grid-cols-2"><DateFilter from={from} to={to} action={`/projects?project=${selected?.id??""}`}/><DimensionReportSelector kind="project" options={(projects??[]).map(({id,code,name,is_active})=>({id,code,name,is_active}))} selectedId={selected?.id??""} from={from} to={to}/></div>
   {q.project&&!selected?<EmptyState title="Project not found" description="Choose a project in this organization."/>:null}
   {selected&&<><div className="my-4 flex flex-wrap items-center justify-between gap-3"><div><p className="font-medium">{selected.code} · {selected.name}</p><p className="text-xs text-slate-500">Posted and reversed entries · {from} to {to}</p></div><CsvExport filename={`project-${selected.code}-${from}-${to}.csv`} headers={["Account code","Account","Type","Debits","Credits","Net activity"]} rows={csvRows}/></div>
    {activityError?<EmptyState title="Project report unavailable" description={activityError.message}/>:<><div className="mb-4 grid gap-3 sm:grid-cols-3"><Card className="p-4"><p className="text-xs text-slate-500">Revenue</p><strong className="mt-2 block">{formatMoney(revenues,org.base_currency)}</strong></Card><Card className="p-4"><p className="text-xs text-slate-500">Expenses</p><strong className="mt-2 block">{formatMoney(expenses,org.base_currency)}</strong></Card><Card className="p-4"><p className="text-xs text-slate-500">Net project activity</p><strong className="mt-2 block">{formatMoney(result,org.base_currency)}</strong></Card></div><DataTable rows={reportRows as unknown as Record<string,unknown>[]} columns={[{key:"code",label:"Code"},{key:"name",label:"Account"},{key:"type",label:"Type",render:r=><span className="capitalize">{String(r.type)}</span>},{key:"debit_display",label:`Debits (${org.base_currency})`},{key:"credit_display",label:`Credits (${org.base_currency})`},{key:"balance_display",label:"Net activity"}]} empty="No posted activity allocated to this project for the selected dates."/></>}
   </>}
  </Card>
  <p className="text-xs leading-5 text-slate-400">Journal lines can be allocated to one department and one project. Reports use posted and reversed functional-currency amounts; unallocated lines are excluded. Deactivated dimensions remain available in historical reports.</p>
 </>;
}
