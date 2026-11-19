import {getWorkspace} from "@/lib/data";
import {Card,EmptyState,PageHeader} from "@/components/ui";
import {DateFilter} from "@/components/date-filter";
import {DataTable} from "@/components/data-table";
import {CsvExport} from "@/components/csv-export";

export const metadata={title:"Financial ratios"};
const descriptions:Record<string,string>={
  debt_to_equity:"Total posted liabilities divided by equity including unclosed earnings, as of the selected date.",
  net_profit_margin:"Period profit or loss as a percentage of period income.",
  return_on_assets:"Period profit or loss as a percentage of posted assets as of the selected date.",
  return_on_equity:"Period profit or loss as a percentage of equity, including unclosed earnings, as of the selected date.",
  debt_to_assets:"Total posted liabilities divided by posted assets as of the selected date.",
  expense_to_income:"Period expenses as a percentage of period income.",
  cash_to_payables:"Classified cash and bank balances divided by classified payables, as of the selected date.",
};

export default async function FinancialRatiosPage({searchParams}:{searchParams:Promise<{from?:string;to?:string}>}){
  const {org,supabase}=await getWorkspace();if(!org||!supabase)return null;
  const query=await searchParams;const today=new Date().toISOString().slice(0,10);
  const from=query.from??`${today.slice(0,4)}-01-01`;const to=query.to??today;
  const {data,error}=await supabase.rpc("financial_ratios_exact",{p_org:org.id,p_from:from,p_to:to,p_as_of:to});
  const rows=(data??[]).map((row,index)=>({...row,id:`ratio-${index}`,description:descriptions[row.ratio_key]??"Derived from posted accounting activity.",display:row.value===null?"N/A":`${row.value} ${row.unit}`}));
  const csvRows=(data??[]).map(row=>[row.label,row.numerator,row.denominator,row.value??"N/A",row.unit,descriptions[row.ratio_key]??""]);
  return <>
    <PageHeader eyebrow={org.name} title="Financial ratios" description={`Calculated from posted and reversed ledger activity in ${org.base_currency}. Balances are as of ${to}; income and expenses cover ${from} through ${to}.`} action={<CsvExport filename={`financial-ratios-${from}-${to}.csv`} headers={["Ratio","Numerator","Denominator","Value","Unit","Definition"]} rows={csvRows}/>}/>
    <Card className="mb-5 p-4 md:p-5"><DateFilter from={from} to={to} action="/reports/ratios"/></Card>
    {error?<Card><EmptyState title="Financial ratios unavailable" description={`${error.message}. Apply migration 016 after reviewing the complete migration sequence.`}/></Card>:<Card className="p-4 md:p-5"><DataTable rows={rows as unknown as Record<string,unknown>[]} columns={[{key:"label",label:"Ratio"},{key:"display",label:"Value"},{key:"numerator",label:"Numerator"},{key:"denominator",label:"Denominator"},{key:"description",label:"Definition"}]} empty="No posted activity is available for this reporting period."/></Card>}
    <p className="mt-4 text-xs leading-5 text-slate-500">A zero denominator is shown as N/A. Cash-to-payables includes only explicitly classified cash, bank, and payable accounts. Review account classifications and your organization’s reporting policy before relying on these indicators.</p>
  </>;
}
