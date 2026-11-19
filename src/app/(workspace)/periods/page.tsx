import {getWorkspace} from "@/lib/data";
import type {ReactNode} from "react";
import {Card,PageHeader,EmptyState} from "@/components/ui";
import {DataTable} from "@/components/data-table";
import {FiscalYearCloseControl,PeriodCreate,PeriodToggle} from "@/components/period-controls";

export const metadata={title:"Accounting periods"};
export default async function PeriodsPage(){
  const {org,supabase}=await getWorkspace();if(!org||!supabase)return null;
  const [{data:periods,error},{data:closings,error:closeError},{data:accounts,error:accountsError}]=await Promise.all([
    supabase.from("accounting_periods").select("id,start_date,end_date,is_closed").eq("org_id",org.id).order("start_date",{ascending:false}),
    supabase.from("fiscal_year_closings").select("id,period_id,journal_entry_id,status").eq("org_id",org.id).order("fiscal_year_end",{ascending:false}),
    supabase.from("accounts").select("id,code,name").eq("org_id",org.id).eq("type","equity").eq("is_active",true).order("code"),
  ]);
  const canManage=["owner","administrator","accountant","finance_manager"].includes(org.role);
  const closeMonth=(org.fy_start_month+10)%12+1;
  const rows=(periods??[]).map(period=>{
    const isYearEnd=Number(period.end_date.slice(5,7))===closeMonth;
    const closing=closings?.find(item=>item.period_id===period.id);
    return {...period,status:period.is_closed?"Closed":"Open",action:canManage?(isYearEnd
      ?closeError?<span className="text-xs text-amber-700">Fiscal-year close is unavailable: {closeError.message}</span>
        :accountsError?<span className="text-xs text-red-700">Retained earnings accounts unavailable: {accountsError.message}</span>
        :accounts?.length===0?<span className="text-xs text-amber-700">Add an active equity account before closing this year</span>
        :<FiscalYearCloseControl orgId={org.id} periodId={period.id} periodLabel={period.end_date.slice(0,4)} closed={period.is_closed} closing={closing as never} accounts={(accounts??[]) as never[]}/>
      :<PeriodToggle id={period.id} closed={period.is_closed}/>):<span className="text-xs text-slate-400">View only</span>};
  });
  return <>
    <PageHeader eyebrow={org.name} title="Accounting periods" description="Maintain monthly reporting periods, prepare fiscal-year closing journals, and protect closed dates from posting." action={(["owner","finance_manager"].includes(org.role))?<PeriodCreate orgId={org.id}/>:null}/>
    {closeError&&<p role="status" className="mb-4 rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-900">Fiscal-year close data could not be loaded: {closeError.message}. Apply migration 024 if it has not been applied; otherwise verify database access. Existing monthly period controls remain available.</p>}
    <Card className="p-4 md:p-5">{error?<EmptyState title="Periods unavailable" description={error.message}/>:<DataTable rows={rows as unknown as Record<string,unknown>[]} columns={[
      {key:"start_date",label:"Start date"},{key:"end_date",label:"End date"},
      {key:"status",label:"Status",render:r=><span className={`rounded-full px-2 py-1 text-[10px] ${r.status==="Closed"?"bg-red-50 text-red-700":"bg-green-50 text-green-700"}`}>{String(r.status)}</span>},
      {key:"action",label:"Period action",render:r=>r.action as ReactNode},
    ]} empty="No accounting periods have been configured."/>}</Card>
    <p className="mt-3 text-xs text-slate-400">Year-end close journals use the selected retained earnings account and require separate approval. Monthly periods can be locked without a fiscal-year transfer. Reversing a year-end close is required before reopening that fiscal year.</p>
  </>;
}
