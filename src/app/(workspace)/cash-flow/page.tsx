import {z} from "zod";
import {getWorkspace} from "@/lib/data";
import {Card,EmptyState,PageHeader} from "@/components/ui";
import {DateFilter} from "@/components/date-filter";
import {DataTable} from "@/components/data-table";
import {CsvExport} from "@/components/csv-export";
import {formatMoney,isZeroDecimal} from "@/lib/utils";

export const metadata={title:"Cash flow statement"};
const sectionLabels:Record<string,string>={operating:"Operating activities",investing:"Investing activities",financing:"Financing activities",unclassified:"Unclassified activities",net_change:"Net change in cash",opening_cash:"Cash and equivalents at start",closing_cash:"Cash and equivalents at end",ledger_cash_movement:"Ledger cash movement",reconciliation_difference:"Reconciliation difference"};
export default async function CashFlowPage({searchParams}:{searchParams:Promise<{from?:string;to?:string}>}){
 const {org,supabase}=await getWorkspace();if(!org||!supabase)return null;
 const q=await searchParams;const today=new Date().toLocaleDateString("en-CA",{timeZone:"Asia/Karachi"});
 const {data:settings}=await supabase.from("organizations").select("fy_start_month").eq("id",org.id).single();
 const startMonth=settings?.fy_start_month??1;const year=Number(today.slice(0,4))-(Number(today.slice(5,7))<startMonth?1:0);
 const defaultFrom=`${year}-${String(startMonth).padStart(2,"0")}-01`;
 const from=z.iso.date().safeParse(q.from).success?q.from!:defaultFrom;const to=z.iso.date().safeParse(q.to).success?q.to!:today;
 const {data,error}=await supabase.rpc("cash_flow_statement_exact",{p_org:org.id,p_from:from,p_to:to});
 const amounts=new Map<string,string>((data??[]).map(r=>[r.section,r.amount]));const val=(section:string)=>amounts.get(section)??"0";
 const rows=(data??[]).map((r,i)=>({id:String(i),section:sectionLabels[r.section]??r.section,amount:r.amount,kind:r.section}));
 const csvRows=rows.map(r=>[r.section,r.amount,org.base_currency]);const unclassified=val("unclassified");const difference=val("reconciliation_difference");
 return <>
  <PageHeader eyebrow={org.name} title="Cash flow statement" description={`Direct cash-flow activity from posted journal entries, in ${org.base_currency}.` } action={<CsvExport filename={`linkora-cash-flow-${from}-${to}.csv`} headers={["Section","Amount","Currency"]} rows={csvRows}/>}/>
  <Card className="mb-5 p-4 md:p-5"><DateFilter from={from} to={to} action="/cash-flow"/></Card>
  {error?<Card><EmptyState title="Cash flow unavailable" description={error.message}/></Card>:<>
   <div className="mb-4 grid gap-3 sm:grid-cols-3"><Card className="p-4"><p className="text-xs text-slate-500">Opening cash & equivalents</p><p className="mt-2 text-xl font-bold tabular-nums">{formatMoney(val("opening_cash"),org.base_currency)}</p></Card><Card className="p-4"><p className="text-xs text-slate-500">Net change</p><p className="mt-2 text-xl font-bold tabular-nums">{formatMoney(val("net_change"),org.base_currency)}</p></Card><Card className="p-4"><p className="text-xs text-slate-500">Closing cash & equivalents</p><p className="mt-2 text-xl font-bold tabular-nums">{formatMoney(val("closing_cash"),org.base_currency)}</p></Card></div>
   {!isZeroDecimal(unclassified)&&<Card className="mb-4 border-amber-300 bg-amber-50 p-4 text-sm text-amber-900">Some cash movements have unclassified counterpart accounts ({formatMoney(unclassified,org.base_currency)}). Review Cash-flow class in the Chart of Accounts before relying on the activity categories.</Card>}
   {!isZeroDecimal(difference)&&<Card className="mb-4 border-red-300 bg-red-50 p-4 text-sm text-red-800">Cash-flow totals do not reconcile to cash and bank ledger movements. Difference: {formatMoney(difference,org.base_currency)}.</Card>}
   <Card className="p-4 md:p-5"><div className="mb-3"><h2 className="font-semibold">Cash flow detail</h2><p className="mt-1 text-xs text-slate-500">Cash and bank transfers are excluded from activity categories; the report shows unclassified counterpart activity separately.</p></div><DataTable rows={rows as unknown as Record<string,unknown>[]} columns={[{key:"section",label:"Section"},{key:"amount",label:`Amount (${org.base_currency})`,render:r=><span className="tabular-nums">{formatMoney(String(r.amount),org.base_currency)}</span>}]} empty="No posted cash activity exists for this period." searchable={false}/></Card>
  </>}
  <p className="mt-4 text-xs leading-5 text-slate-400">Cash-flow classifications are account-based and auditable. Unclassified amounts stay visible, and the report reconciles activity against cash and bank ledger movement; this report does not apply jurisdiction-specific financial reporting policies automatically.</p>
 </>;
}
