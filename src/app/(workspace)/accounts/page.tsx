import {getWorkspace} from "@/lib/data";
import {Card,PageHeader,EmptyState} from "@/components/ui";
import {DataTable} from "@/components/data-table";
import {AccountForm} from "@/components/account-form";
import {AccountReportingClass} from "@/components/account-reporting-class";
import {AccountCashFlowClass} from "@/components/account-cash-flow-class";
import {formatMoney,negateDecimal,sumDecimals} from "@/lib/utils";

export const metadata={title:"Chart of accounts"};
export default async function AccountsPage(){
  const {org,supabase}=await getWorkspace();if(!org||!supabase)return null;
  const [{data:accounts,error},{data:trial,error:trialError}]=await Promise.all([
    supabase.from("accounts").select("id,code,name,type,description,normal_balance,is_active,parent_id,reporting_class,cash_flow_class,created_at").eq("org_id",org.id).order("code"),
    supabase.rpc("trial_balance_exact",{p_org:org.id,p_from:"0001-01-01",p_to:new Date().toISOString().slice(0,10)}),
  ]);
  const byCode=new Map((trial??[]).map(r=>[r.code,sumDecimals([r.debit,negateDecimal(r.credit)])]));
  return <>
    <PageHeader eyebrow={org.name} title="Chart of accounts" description="Manage the accounts used to organize and report on financial activity." action={(["owner","administrator","accountant"].includes(org.role))?<AccountForm orgId={org.id}/>:null}/>
    <Card className="p-4 md:p-5">{error||trialError?<EmptyState title="Accounts unavailable" description={(error??trialError)?.message??"Unable to load account balances."}/>:<DataTable rows={(accounts??[]).map(a=>{const net=byCode.get(a.code)??"0";const normalBalance=a.reporting_class==="accumulated_depreciation"?"credit":a.normal_balance;return {id:a.id,code:a.code,name:a.name,type:a.type,reporting_class:a.reporting_class,cash_flow_class:a.cash_flow_class,normal_balance:normalBalance,status:a.is_active?"Active":"Inactive",balance:normalBalance==="debit"?net:negateDecimal(net)}}) as unknown as Record<string,unknown>[]} columns={[{key:"code",label:"Code"},{key:"name",label:"Account"},{key:"type",label:"Type",render:r=><span className="capitalize">{String(r.type)}</span>},{key:"reporting_class",label:"Dashboard / accounting class",render:r=><AccountReportingClass orgId={org.id} accountId={String(r.id)} type={String(r.type)} value={(r.reporting_class??null) as "cash"|"bank"|"receivable"|"payable"|"accumulated_depreciation"|null} canEdit={["owner","administrator","accountant"].includes(org.role)}/>},{key:"cash_flow_class",label:"Cash-flow class",render:r=><AccountCashFlowClass orgId={org.id} accountId={String(r.id)} reportingClass={(r.reporting_class??null) as string|null} value={r.cash_flow_class as "operating"|"investing"|"financing"|"unclassified"} canEdit={["owner","administrator","accountant"].includes(org.role)}/>},{key:"normal_balance",label:"Normal balance",render:r=><span className="capitalize">{r.reporting_class==="accumulated_depreciation"?"Credit (contra asset)":String(r.normal_balance)}</span>},{key:"balance",label:`Balance (${org.base_currency})`,render:r=><span className="font-medium tabular-nums">{formatMoney(String(r.balance),org.base_currency)}</span>},{key:"status",label:"Status",render:r=><span className={`rounded-full px-2 py-1 text-[10px] ${r.status==="Active"?"bg-green-50 text-green-700":"bg-slate-100 text-slate-500"}`}>{String(r.status)}</span>}]} empty="No accounts found."/>}</Card>
    <p className="mt-3 text-xs text-slate-400">Balances use the exact decimal trial balance read model. Dashboard cash, bank, receivable, and payable totals use explicit account classifications. Posted account identity remains protected; classification changes are audited.</p>
  </>;
}
