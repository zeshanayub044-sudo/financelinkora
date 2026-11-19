import Link from "next/link";
import { getWorkspace } from "@/lib/data";
import { BudgetApprovalButton, BudgetForm, type BudgetDraft } from "@/components/budget-form";
import { CsvExport } from "@/components/csv-export";
import { DataTable } from "@/components/data-table";
import { Card, EmptyState, PageHeader } from "@/components/ui";
import { formatMoney } from "@/lib/utils";

export const metadata={title:"Budgets"};
export default async function BudgetsPage({searchParams}:{searchParams:Promise<{budget?:string}>}){
  const {org,supabase,user}=await getWorkspace();if(!org||!supabase)return null;
  const query=await searchParams;
  const [{data:budgets,error:budgetError},{data:accounts,error:accountError}]=await Promise.all([
    supabase.from("budgets").select("id,name,start_date,end_date,status,created_by,approved_by,approved_at,created_at").eq("org_id",org.id).order("created_at",{ascending:false}),
    supabase.from("accounts").select("id,code,name,type").eq("org_id",org.id).eq("is_active",true).in("type",["revenue","expense"]).order("code"),
  ]);
  const selected=budgets?.find(row=>row.id===query.budget);
  const {data:variance,error:varianceError}=selected
    ?await supabase.rpc("budget_variance_exact",{p_budget:selected.id})
    :{data:null,error:null};
  const canCreate=["owner","administrator","accountant","finance_manager"].includes(org.role);
  const canApprove=["owner","finance_manager","approver"].includes(org.role)&&Boolean(selected&&selected.created_by!==user?.id);
  const initial:BudgetDraft|undefined=selected?.status==="draft"&&selected.created_by===user?.id?{
    id:selected.id,name:selected.name,start_date:selected.start_date,end_date:selected.end_date,
    lines:(variance??[]).map(row=>({account_id:row.account_id,period_start:row.period_start,amount:row.budget})),
  }:undefined;
  const budgetRows=(budgets??[]).map(row=>({...row,id:row.id,status:row.status,range:`${row.start_date} – ${row.end_date}`}));
  const varianceRows=(variance??[]).map((row,index)=>({...row,id:`${row.period_start}-${row.account_id}-${index}`}));
  const csvRows=(variance??[]).map(row=>[row.period_start,row.code,row.name,row.type,row.budget,row.actual,row.actual_minus_budget]);
  const pageError=budgetError??accountError;
  return <>
    <PageHeader eyebrow={org.name} title="Budgets" description="Maintain monthly revenue and expense plans and compare them with posted ledger activity." action={selected&&variance?.length?<CsvExport filename={`linkora-budget-${selected.start_date}.csv`} headers={["Month","Account code","Account","Type","Budget","Posted actual","Actual minus budget"]} rows={csvRows}/>:null}/>
    {pageError?<Card><EmptyState title="Budget data unavailable" description={pageError.message}/></Card>:<>
      <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_minmax(320px,0.8fr)]">
        <Card className="p-4 md:p-5"><h2 className="mb-3 font-semibold">Budget plans</h2><DataTable rows={budgetRows as unknown as Record<string,unknown>[]} columns={[
          {key:"name",label:"Budget",render:row=><Link className="font-semibold text-blue-700 hover:underline" href={`/budgets?budget=${row.id}`}>{String(row.name)}</Link>},
          {key:"range",label:"Date range"},
          {key:"status",label:"Status",render:row=><span className="capitalize">{String(row.status)}</span>},
          {key:"created_at",label:"Created",render:row=>new Date(String(row.created_at)).toLocaleDateString()},
        ]} empty="No budgets yet. Create a draft plan to get started."/></Card>
        {canCreate&&<Card className="p-4 md:p-5"><h2 className="mb-1 font-semibold">{initial?"Edit budget draft":"New budget draft"}</h2><p className="mb-4 text-xs text-slate-500">{initial?"Changes are allowed until another authorized member approves this plan.":"Choose full month boundaries and add monthly account targets."}</p>{accountError?<EmptyState title="Accounts unavailable" description={accountError.message}/>:accounts?.length?<BudgetForm orgId={org.id} baseCurrency={org.base_currency} fyStartMonth={org.fy_start_month??1} accounts={accounts.filter(a=>a.type==="revenue"||a.type==="expense") as {id:string;code:string;name:string;type:"revenue"|"expense"}[]} initial={initial}/>:<EmptyState title="Revenue and expense accounts required" description="Add active income or expense accounts before creating a budget."/>}</Card>}
      </div>
      {selected&&<Card className="mt-5 p-4 md:p-5"><div className="mb-4 flex flex-wrap items-start justify-between gap-3"><div><p className="text-xs uppercase tracking-wide text-slate-500">{selected.status} plan</p><h2 className="mt-1 text-lg font-semibold">{selected.name}</h2><p className="mt-1 text-xs text-slate-500">{selected.start_date} through {selected.end_date} · amounts in {org.base_currency}</p></div>{canApprove&&selected.status==="draft"?<BudgetApprovalButton id={selected.id}/>:null}</div>
        {varianceError?<EmptyState title="Variance report unavailable" description={varianceError.message}/>:<DataTable rows={varianceRows as unknown as Record<string,unknown>[]} columns={[
          {key:"period_start",label:"Month",render:row=>new Date(`${row.period_start}T00:00:00`).toLocaleDateString("en",{month:"short",year:"numeric"})},
          {key:"code",label:"Code"},{key:"name",label:"Account"},{key:"type",label:"Type",render:row=><span className="capitalize">{String(row.type)}</span>},
          {key:"budget",label:`Budget · ${org.base_currency}`,render:row=>formatMoney(String(row.budget),org.base_currency)},
          {key:"actual",label:"Posted actual",render:row=>formatMoney(String(row.actual),org.base_currency)},
          {key:"actual_minus_budget",label:"Actual − budget",render:row=>formatMoney(String(row.actual_minus_budget),org.base_currency)},
        ]} empty="No budget lines. Edit this draft to add monthly targets."/>}
      </Card>}
      <p className="mt-4 text-xs leading-5 text-slate-400">Budget variance uses posted and reversed journal activity in the selected month. Draft budgets are planning records and never post to the General Ledger. The module does not yet support department allocations or carry-forward forecasting.</p>
    </>}
  </>;
}
