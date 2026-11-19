import {Card,Input,Label,PageHeader,EmptyState} from "@/components/ui";
import {DataTable} from "@/components/data-table";
import {formatMoney,sumDecimals} from "@/lib/utils";
import {CsvExport} from "@/components/csv-export";

export type AgingRow={document_id:string;org_id:string;document_type:"invoice"|"bill";document_number:string;party_id:string;party_name:string;issue_date:string;due_date:string;days_past_due:number;outstanding:string;aging_bucket:"current"|"1_30_days"|"31_60_days"|"61_90_days"|"over_90_days"};
const buckets:[AgingRow["aging_bucket"],string][]=[["current","Current"],["1_30_days","1–30 days"],["31_60_days","31–60 days"],["61_90_days","61–90 days"],["over_90_days","Over 90 days"]];

export function FinancialAgingReport({rows,error,currency,asOf,documentType}:{rows:AgingRow[];error?:string;currency:string;asOf:string;documentType:"invoice"|"bill"}){
  const values=Object.fromEntries(buckets.map(([key])=>[key,sumDecimals(rows.filter(row=>row.aging_bucket===key).map(row=>row.outstanding))]));
  const title=documentType==="invoice"?"Receivables aging":"Payables aging";
  const exportRows=rows.map(row=>[row.document_number,row.party_name,row.issue_date,row.due_date,row.days_past_due,row.aging_bucket,row.outstanding]);
  const exportHeaders=["Document","Party","Issue date","Due date","Days past due","Aging bucket","Outstanding"];

  return <section className="mt-7">
    <PageHeader eyebrow="Open balances" title={title} description={`Posted ${documentType==="invoice"?"customer invoices":"supplier bills"} grouped by days past due.`} action={
      <div className="flex flex-wrap items-end gap-2">
        <form method="get" className="flex items-end gap-2 print:hidden">
          <div><Label htmlFor="asOf">As of</Label><Input id="asOf" type="date" name="asOf" defaultValue={asOf}/></div>
          <button className="focus-ring min-h-10 rounded-lg bg-primary px-4 text-sm font-semibold">Run</button>
        </form>
        {!error&&<CsvExport filename={`linkora-${documentType}-aging-${asOf}.csv`} headers={exportHeaders} rows={exportRows}/>}
      </div>
    }/>
    {error?<Card><EmptyState title={`${title} unavailable`} description={error}/></Card>:<>
      <div className="mb-4 grid grid-cols-2 gap-3 lg:grid-cols-5">
        {buckets.map(([key,label])=><Card className="p-4" key={key}><p className="text-xs text-slate-500">{label}</p><p className="mt-2 text-base font-semibold tabular-nums">{formatMoney(values[key],currency)}</p></Card>)}
      </div>
      <Card className="p-4 md:p-5">
        <DataTable rows={rows.map(row=>({...row,outstandingFormatted:formatMoney(row.outstanding,currency),status:row.days_past_due===0?"Current":`${row.days_past_due} days overdue`}))}
          columns={[{key:"document_number",label:"Document"},{key:"party_name",label:documentType==="invoice"?"Customer":"Supplier"},{key:"issue_date",label:"Issued"},{key:"due_date",label:"Due"},{key:"status",label:"Aging"},{key:"outstandingFormatted",label:`Outstanding (${currency})`}]}
          empty={`No open ${documentType==="invoice"?"receivables":"payables"} as of ${asOf}.`}/>
      </Card>
    </>}
  </section>;
}
