import {getWorkspace} from "@/lib/data";
import {Card,EmptyState,PageHeader} from "@/components/ui";
import {DateFilter} from "@/components/date-filter";
import {DataTable} from "@/components/data-table";
import {CsvExport} from "@/components/csv-export";
import {formatMoney} from "@/lib/utils";

export const metadata={title:"Financial statements"};
export default async function StatementsPage({searchParams}:{searchParams:Promise<{from?:string;to?:string}>}){
  const {org,supabase}=await getWorkspace();if(!org||!supabase)return null;
  const q=await searchParams;const today=new Date().toISOString().slice(0,10);
  const {data:settings}=await supabase.from("organizations").select("fy_start_month").eq("id",org.id).single();
  const startMonth=settings?.fy_start_month??1;const y=Number(today.slice(0,4))-(Number(today.slice(5,7))<startMonth?1:0);
  const from=q.from??`${y}-${String(startMonth).padStart(2,"0")}-01`;const to=q.to??today;
  const [{data:pnl,error:pnlError},{data:balance,error:balanceError},{data:summary,error:summaryError}]=await Promise.all([
    supabase.rpc("profit_and_loss",{p_org:org.id,p_from:from,p_to:to}),
    supabase.rpc("balance_sheet",{p_org:org.id,p_as_of:to}),
    supabase.rpc("financial_summary",{p_org:org.id,p_from:from,p_to:to,p_as_of:to}),
  ]);
  const rows=(pnl??[]).map((r,i)=>({...r,id:`pnl-${i}`,amount:Number(r.amount)}));
  const bs=(balance??[]).map((r,i)=>({...r,id:`bs-${i}`,balance:Number(r.balance)}));
  const totals=summary?.[0];const assets=Number(totals?.assets??0);const liabilities=Number(totals?.liabilities??0);const equity=Number(totals?.equity??0);const difference=assets-liabilities-equity;
  const revenue=rows.filter(r=>r.type==="revenue").reduce((sum,r)=>sum+r.amount,0);const expense=rows.filter(r=>r.type==="expense").reduce((sum,r)=>sum+r.amount,0);
  const csvRows=[...(pnl??[]).map(r=>["Profit and Loss",r.type,r.code,r.name,String(r.amount)]),...(balance??[]).map(r=>["Balance Sheet",r.section,r.code,r.name,String(r.balance)])];
  const error=pnlError??balanceError??summaryError;
  return <>
    <PageHeader eyebrow={org.name} title="Financial statements" description={`Posted-ledger reports in ${org.base_currency}. Income and expenses cover the selected period; balance sheet is as of the end date.`} action={<CsvExport filename={`linkora-statements-${to}.csv`} headers={["Report","Section","Code","Account","Amount"]} rows={csvRows}/>}/>
    <Card className="mb-5 p-4 md:p-5"><DateFilter from={from} to={to}/></Card>
    {error?<Card><EmptyState title="Statements unavailable" description={error.message}/></Card>:<>
      <div className="grid gap-3 sm:grid-cols-3"><Card className="p-4"><p className="text-xs text-slate-500">Revenue · period</p><p className="mt-2 text-xl font-bold">{formatMoney(revenue,org.base_currency)}</p></Card><Card className="p-4"><p className="text-xs text-slate-500">Expenses · period</p><p className="mt-2 text-xl font-bold">{formatMoney(expense,org.base_currency)}</p></Card><Card className="p-4"><p className="text-xs text-slate-500">Profit / (loss) · period</p><p className="mt-2 text-xl font-bold">{formatMoney(revenue-expense,org.base_currency)}</p></Card></div>
      <div className="mt-5 grid gap-5 xl:grid-cols-2"><Card className="p-4 md:p-5"><h2 className="mb-3 font-semibold">Profit and loss</h2><DataTable rows={rows as unknown as Record<string,unknown>[]} columns={[{key:"code",label:"Code"},{key:"name",label:"Account"},{key:"type",label:"Type",render:r=><span className="capitalize">{String(r.type)}</span>},{key:"amount",label:`Amount (${org.base_currency})`,render:r=>formatMoney(Number(r.amount),org.base_currency)}]} empty="No posted income or expense entries in this period."/></Card>
      <Card className="p-4 md:p-5"><div className="mb-3 flex items-center justify-between gap-2"><div><h2 className="font-semibold">Balance sheet</h2><p className="mt-1 text-xs text-slate-500">As of {to}</p></div><span className={`rounded-full px-2 py-1 text-xs font-semibold ${Math.abs(difference)<0.0001?"bg-green-50 text-green-700":"bg-red-50 text-red-700"}`}>{Math.abs(difference)<0.0001?"Balances":"Out of balance"}</span></div><DataTable rows={bs as unknown as Record<string,unknown>[]} columns={[{key:"section",label:"Section",render:r=><span className="capitalize">{String(r.section)}</span>},{key:"code",label:"Code"},{key:"name",label:"Account"},{key:"balance",label:`Balance (${org.base_currency})`,render:r=>formatMoney(Number(r.balance),org.base_currency)}]} empty="No posted balance sheet activity yet."/><div className="mt-4 grid gap-2 border-t border-border pt-4 text-sm sm:grid-cols-3"><p>Assets <strong className="block">{formatMoney(assets,org.base_currency)}</strong></p><p>Liabilities <strong className="block">{formatMoney(liabilities,org.base_currency)}</strong></p><p>Equity <strong className="block">{formatMoney(equity,org.base_currency)}</strong></p></div></Card></div>
    </>}
    <p className="mt-4 text-xs leading-5 text-slate-400">Reports include posted and reversed journal entries only. Opening balances, cash-flow classification, foreign-currency revaluation, and year-end close workflows have not been implemented. Validate accounting policy and reconcile these statements before operational use.</p>
  </>;
}

