import {getWorkspace} from "@/lib/data";
import {Card,EmptyState,PageHeader} from "@/components/ui";
import {DateFilter} from "@/components/date-filter";
import {DataTable} from "@/components/data-table";
import {CsvExport} from "@/components/csv-export";
import {balanceSheetDifference,formatMoney,negateDecimal,sumDecimals} from "@/lib/utils";

export const metadata={title:"Financial statements"};
export default async function StatementsPage({searchParams}:{searchParams:Promise<{from?:string;to?:string}>}){
  const {org,supabase}=await getWorkspace();if(!org||!supabase)return null;
  const q=await searchParams;const today=new Date().toISOString().slice(0,10);
  const {data:settings}=await supabase.from("organizations").select("fy_start_month").eq("id",org.id).single();
  const startMonth=settings?.fy_start_month??1;const y=Number(today.slice(0,4))-(Number(today.slice(5,7))<startMonth?1:0);
  const from=q.from??`${y}-${String(startMonth).padStart(2,"0")}-01`;const to=q.to??today;
  const [{data:pnl,error:pnlError},{data:balance,error:balanceError},{data:summary,error:summaryError},{data:equityChanges,error:equityError}]=await Promise.all([
    supabase.rpc("profit_and_loss_exact",{p_org:org.id,p_from:from,p_to:to}),
    supabase.rpc("balance_sheet_exact",{p_org:org.id,p_as_of:to}),
    supabase.rpc("financial_summary_exact",{p_org:org.id,p_from:from,p_to:to,p_as_of:to}),
    supabase.rpc("statement_of_changes_in_equity_exact",{p_org:org.id,p_from:from,p_to:to}),
  ]);
  const rows=(pnl??[]).map((r,i)=>({...r,id:`pnl-${i}`}));
  const bs=(balance??[]).map((r,i)=>({...r,id:`bs-${i}`}));
  const totals=summary?.[0];const assets=totals?.assets??"0";const liabilities=totals?.liabilities??"0";const equity=totals?.equity??"0";const difference=balanceSheetDifference(assets,liabilities,equity);
  const revenue=sumDecimals((pnl??[]).filter(r=>r.type==="revenue").map(r=>r.amount));const expense=sumDecimals((pnl??[]).filter(r=>r.type==="expense").map(r=>r.amount));
  const csvRows=[...(pnl??[]).map(r=>["Profit and Loss",r.type,r.code,r.name,String(r.amount)]),...(balance??[]).map(r=>["Balance Sheet",r.section,r.code,r.name,String(r.balance)])];
  const equityCsvRows=(equityChanges??[]).map(r=>[r.line_type,r.code??"",r.name,r.opening_balance,r.period_movement,r.closing_balance]);
  const error=pnlError??balanceError??summaryError;
  return <>
    <PageHeader eyebrow={org.name} title="Financial statements" description={`Posted-ledger reports in ${org.base_currency}. Income, expenses, and equity movements cover the selected period; balance sheet is as of the end date.`} action={<div className="flex flex-wrap gap-2"><CsvExport filename={`linkora-statements-${to}.csv`} headers={["Report","Section","Code","Account","Amount"]} rows={csvRows}/><CsvExport filename={`linkora-equity-changes-${from}-${to}.csv`} headers={["Line type","Code","Account","Opening balance","Period movement","Closing balance"]} rows={equityCsvRows}/></div>}/>
    <Card className="mb-5 p-4 md:p-5"><DateFilter from={from} to={to} action="/statements"/></Card>
    {error?<Card><EmptyState title="Statements unavailable" description={error.message}/></Card>:<>
      <div className="grid gap-3 sm:grid-cols-3"><Card className="p-4"><p className="text-xs text-slate-500">Revenue · period</p><p className="mt-2 text-xl font-bold">{formatMoney(revenue,org.base_currency)}</p></Card><Card className="p-4"><p className="text-xs text-slate-500">Expenses · period</p><p className="mt-2 text-xl font-bold">{formatMoney(expense,org.base_currency)}</p></Card><Card className="p-4"><p className="text-xs text-slate-500">Profit / (loss) · period</p><p className="mt-2 text-xl font-bold">{formatMoney(sumDecimals([revenue,negateDecimal(expense)]),org.base_currency)}</p></Card></div>
      <div className="mt-5 grid gap-5 xl:grid-cols-2"><Card className="p-4 md:p-5"><h2 className="mb-3 font-semibold">Profit and loss</h2><DataTable rows={rows as unknown as Record<string,unknown>[]} columns={[{key:"code",label:"Code"},{key:"name",label:"Account"},{key:"type",label:"Type",render:r=><span className="capitalize">{String(r.type)}</span>},{key:"amount",label:`Amount (${org.base_currency})`,render:r=>formatMoney(String(r.amount),org.base_currency)}]} empty="No posted income or expense entries in this period."/></Card>
      <Card className="p-4 md:p-5"><div className="mb-3 flex items-center justify-between gap-2"><div><h2 className="font-semibold">Balance sheet</h2><p className="mt-1 text-xs text-slate-500">As of {to}</p></div><span className={`rounded-full px-2 py-1 text-xs font-semibold ${difference==="0"?"bg-green-50 text-green-700":"bg-red-50 text-red-700"}`}>{difference==="0"?"Balances":"Out of balance"}</span></div><DataTable rows={bs as unknown as Record<string,unknown>[]} columns={[{key:"section",label:"Section",render:r=><span className="capitalize">{String(r.section)}</span>},{key:"code",label:"Code"},{key:"name",label:"Account"},{key:"balance",label:`Balance (${org.base_currency})`,render:r=>formatMoney(String(r.balance),org.base_currency)}]} empty="No posted balance sheet activity yet."/><div className="mt-4 grid gap-2 border-t border-border pt-4 text-sm sm:grid-cols-3"><p>Assets <strong className="block">{formatMoney(assets,org.base_currency)}</strong></p><p>Liabilities <strong className="block">{formatMoney(liabilities,org.base_currency)}</strong></p><p>Equity <strong className="block">{formatMoney(equity,org.base_currency)}</strong></p></div></Card></div>
      <Card className="mt-5 p-4 md:p-5"><div className="mb-1"><h2 className="font-semibold">Statement of changes in equity</h2><p className="mt-1 text-xs text-slate-500">Opening balances, posted period movement, and closing balances for {from} through {to}. Undistributed earnings include unclosed historical and current profit or loss.</p></div>{equityError?<EmptyState title="Equity report unavailable" description="Apply migration 013 to enable this report."/>:<DataTable rows={(equityChanges??[]).map((r,i)=>({...r,id:`equity-${i}`})) as unknown as Record<string,unknown>[]} columns={[{key:"code",label:"Code",render:r=>String(r.code??"—")},{key:"name",label:"Equity account"},{key:"opening_balance",label:"Opening",render:r=>formatMoney(String(r.opening_balance),org.base_currency)},{key:"period_movement",label:"Movement",render:r=>formatMoney(String(r.period_movement),org.base_currency)},{key:"closing_balance",label:"Closing",render:r=>formatMoney(String(r.closing_balance),org.base_currency)}]} empty="No equity accounts or earnings are available for this period."/>}</Card>
    </>}
    <p className="mt-4 text-xs leading-5 text-slate-400">Reports include posted and reversed journal entries only. The equity statement presents journal movement by equity account and undistributed earnings; it does not infer contribution or distribution labels. Opening-balance controls are implemented in migration 001 but have not been deployed or live verified. Fiscal-year close journals and period locking are implemented in migration 024 but have not been SQL-tested or verified against the hosted project. Foreign-currency revaluation is not implemented. Validate accounting policy and reconcile these statements before operational use.</p>
  </>;
}
