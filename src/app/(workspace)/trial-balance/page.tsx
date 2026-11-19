import {getWorkspace} from "@/lib/data";
import {Card,PageHeader,EmptyState,Button,Input,Label} from "@/components/ui";
import {DataTable} from "@/components/data-table";
import {CsvExport} from "@/components/csv-export";
import {formatMoney,trialBalanceTotals} from "@/lib/utils";

export const metadata={title:"Trial balance"};
export default async function TrialBalancePage({searchParams}:{searchParams:Promise<{asOf?:string}>}){
  const {org,supabase}=await getWorkspace();if(!org||!supabase)return null;
  const q=await searchParams;const asOf=q.asOf??new Date().toISOString().slice(0,10);
  const {data,error}=await supabase.rpc("trial_balance_as_of_exact",{p_org:org.id,p_as_of:asOf});
  const rows=(data??[]).map((r,i)=>({...r,id:`${r.code}-${i}`}));
  const csvRows=(data??[]).map(r=>[r.code,r.name,r.type,r.debit,r.credit]);
  const totals=trialBalanceTotals(data??[]);
  return <>
    <PageHeader eyebrow={org.name} title="Trial balance" description={`Cumulative debit and credit balances for posted and reversed entries as of ${asOf}.`} action={!error?<CsvExport filename={`linkora-trial-balance-${asOf}.csv`} headers={["Account code","Account","Type","Debit","Credit"]} rows={csvRows}/>:null}/>
    <Card className="mb-5 p-4 md:p-5"><form className="flex flex-wrap items-end gap-3" action="/trial-balance"><div><Label htmlFor="asOf">As of</Label><Input id="asOf" name="asOf" type="date" defaultValue={asOf}/></div><Button>Run report</Button></form></Card>
    <Card className="p-4 md:p-5">{error?<EmptyState title="Trial balance unavailable" description={error.message}/>:<>
      <DataTable rows={rows as unknown as Record<string,unknown>[]} columns={[{key:"code",label:"Code"},{key:"name",label:"Account"},{key:"type",label:"Type",render:r=><span className="capitalize">{String(r.type)}</span>},{key:"debit",label:"Debit",render:r=>formatMoney(String(r.debit),org.base_currency)},{key:"credit",label:"Credit",render:r=>formatMoney(String(r.credit),org.base_currency)}]} empty="No posted activity as of this date."/>
      <div className="mt-3 flex flex-wrap justify-end gap-6 border-t border-border pt-3 text-sm font-bold"><span>Total debits&nbsp; {formatMoney(totals.debit,org.base_currency)}</span><span>Total credits&nbsp; {formatMoney(totals.credit,org.base_currency)}</span><span className={totals.balanced?"text-emerald-700":"text-red-700"}>{totals.balanced?"Balanced":"Out of balance"}</span></div>
    </>}</Card>
  </>;
}
