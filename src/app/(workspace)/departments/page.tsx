import Link from "next/link";
import {getWorkspace} from "@/lib/data";
import {Card,EmptyState,PageHeader} from "@/components/ui";
import {DataTable} from "@/components/data-table";
import {CsvExport} from "@/components/csv-export";
import {DateFilter} from "@/components/date-filter";
import {DimensionActiveControl,DimensionCreateForm,DimensionReportSelector} from "@/components/dimensions-workspace";
import {formatMoney,negateDecimal,sumDecimals} from "@/lib/utils";

export const metadata={title:"Departments"};
export default async function DepartmentsPage({searchParams}:{searchParams:Promise<{from?:string;to?:string;department?:string}>}){
 const {org,supabase}=await getWorkspace();if(!org||!supabase)return null;const q=await searchParams;const today=new Date().toISOString().slice(0,10);const from=q.from??`${today.slice(0,4)}-01-01`;const to=q.to??today;
 const [{data:departments,error:departmentError},{data:activity,error:activityError}]=await Promise.all([
  supabase.from("departments").select("id,org_id,code,name,description,is_active,created_at").eq("org_id",org.id).order("code"),
  q.department?supabase.rpc("dimension_activity_exact",{p_org:org.id,p_from:from,p_to:to,p_dimension_type:"department",p_dimension:q.department}):Promise.resolve({data:null,error:null}),
 ]);
 const selected=departments?.find(d=>d.id===q.department);const canManage=["owner","administrator","accountant","finance_manager"].includes(org.role);
 const revenues=sumDecimals((activity??[]).filter(r=>r.type==="revenue").map(r=>r.balance));const expenses=sumDecimals((activity??[]).filter(r=>r.type==="expense").map(r=>r.balance));const result=sumDecimals([revenues,negateDecimal(expenses)]);
 const reportRows=(activity??[]).map((r,i)=>({...r,id:`activity-${i}`,debit_display:formatMoney(r.debit,org.base_currency),credit_display:formatMoney(r.credit,org.base_currency),balance_display:formatMoney(r.balance,org.base_currency)}));
 const csvRows=(activity??[]).map(r=>[r.code,r.name,r.type,r.debit,r.credit,r.balance]);
 return <>
  <PageHeader eyebrow={org.name} title="Departments" description="Maintain departments and review posted-ledger activity allocated to each one." action={<Link className="rounded-lg border border-border px-3 py-2 text-sm text-blue-700" href="/projects">Projects →</Link>}/>
  {canManage&&<Card className="mb-5 p-4 md:p-5"><h2 className="mb-3 font-semibold">Create department</h2><DimensionCreateForm orgId={org.id} kind="department"/></Card>}
  <Card className="mb-5 p-4 md:p-5"><h2 className="mb-3 font-semibold">Department register</h2>{departmentError?<EmptyState title="Departments unavailable" description={departmentError.message}/>:<DataTable rows={(departments??[]).map(d=>({...d,status:<DimensionActiveControl orgId={org.id} kind="department" id={d.id} isActive={d.is_active} canManage={canManage} />})) as unknown as Record<string,unknown>[]} columns={[{key:"code",label:"Code"},{key:"name",label:"Department"},{key:"description",label:"Description"},{key:"status",label:"Status",render:r=>r.status as React.ReactNode}]} empty="No departments created yet."/>}</Card>
  <Card className="mb-5 p-4 md:p-5"><h2 className="mb-3 font-semibold">Posted activity report</h2><div className="grid gap-3 md:grid-cols-2"><DateFilter from={from} to={to} action={`/departments?department=${selected?.id??""}`}/><DimensionReportSelector kind="department" options={(departments??[]).map(({id,code,name,is_active})=>({id,code,name,is_active}))} selectedId={selected?.id??""} from={from} to={to}/></div>
   {q.department&&!selected?<EmptyState title="Department not found" description="Choose a department in this organization."/>:null}
   {selected&&<><div className="my-4 flex flex-wrap items-center justify-between gap-3"><div><p className="font-medium">{selected.code} · {selected.name}</p><p className="text-xs text-slate-500">Posted and reversed entries · {from} to {to}</p></div><CsvExport filename={`department-${selected.code}-${from}-${to}.csv`} headers={["Account code","Account","Type","Debits","Credits","Net activity"]} rows={csvRows}/></div>
    {activityError?<EmptyState title="Department report unavailable" description={activityError.message}/>:<><div className="mb-4 grid gap-3 sm:grid-cols-3"><Card className="p-4"><p className="text-xs text-slate-500">Revenue</p><strong className="mt-2 block">{formatMoney(revenues,org.base_currency)}</strong></Card><Card className="p-4"><p className="text-xs text-slate-500">Expenses</p><strong className="mt-2 block">{formatMoney(expenses,org.base_currency)}</strong></Card><Card className="p-4"><p className="text-xs text-slate-500">Net activity</p><strong className="mt-2 block">{formatMoney(result,org.base_currency)}</strong></Card></div><DataTable rows={reportRows as unknown as Record<string,unknown>[]} columns={[{key:"code",label:"Code"},{key:"name",label:"Account"},{key:"type",label:"Type",render:r=><span className="capitalize">{String(r.type)}</span>},{key:"debit_display",label:`Debits (${org.base_currency})`},{key:"credit_display",label:`Credits (${org.base_currency})`},{key:"balance_display",label:"Net activity"}]} empty="No posted activity allocated to this department for the selected dates."/></>}
   </>}
  </Card>
  <p className="text-xs leading-5 text-slate-400">Journal lines can be allocated to one department and one project. Reports use posted and reversed functional-currency amounts; unallocated lines are excluded. Deactivated dimensions remain available in historical reports.</p>
 </>;
}
