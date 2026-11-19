import {getWorkspace} from "@/lib/data";
import {Card,PageHeader,EmptyState} from "@/components/ui";
import {DataTable} from "@/components/data-table";
import {CsvExport} from "@/components/csv-export";
import {formatMoney,isZeroDecimal} from "@/lib/utils";

export const metadata={title:"General ledger"};
export default async function LedgerPage(){
  const {org,supabase}=await getWorkspace();if(!org||!supabase)return null;
  const {data,error}=await supabase.from("ledger_exact").select("account_id,code,account_name,entry_no,entry_date,description,memo,debit,credit,running_balance").eq("org_id",org.id).order("entry_date",{ascending:false});
  const rows=(data??[]).map((r,i)=>({...r,id:`${r.entry_no}-${r.account_id}-${i}`}));
  const csvRows=(data??[]).map(r=>[r.entry_date,r.entry_no,r.code,r.account_name,r.description,r.memo,r.debit,r.credit,r.running_balance]);
  const columns=[
    {key:"entry_date",label:"Date"},{key:"entry_no",label:"Entry"},{key:"code",label:"Account code"},{key:"account_name",label:"Account"},{key:"description",label:"Description"},
    {key:"debit",label:"Debit",render:(r:Record<string,unknown>)=>isZeroDecimal(String(r.debit))?"—":formatMoney(String(r.debit),org.base_currency)},
    {key:"credit",label:"Credit",render:(r:Record<string,unknown>)=>isZeroDecimal(String(r.credit))?"—":formatMoney(String(r.credit),org.base_currency)},
    {key:"running_balance",label:"Running balance",render:(r:Record<string,unknown>)=>formatMoney(String(r.running_balance),org.base_currency)},
  ];
  return <><PageHeader eyebrow={org.name} title="General ledger" description="Posted and reversed journal lines with account-level running balances." action={!error?<CsvExport filename="linkora-general-ledger.csv" headers={["Date","Entry","Account code","Account","Description","Line memo","Debit","Credit","Running balance"]} rows={csvRows}/>:null}/><Card className="p-4 md:p-5">{error?<EmptyState title="Ledger unavailable" description={error.message}/>:<DataTable rows={rows as unknown as Record<string,unknown>[]} columns={columns} empty="No posted journal lines yet."/>}</Card></>;
}
