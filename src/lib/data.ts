import { cookies } from "next/headers";
import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import {compareDecimals} from "@/lib/utils";

export const getWorkspace=cache(async function loadWorkspace() {
  const supabase=await createClient();if(!supabase)return {supabase:null,org:null,orgs:[],user:null,error:null as string|null};
  const {data:{user},error:userError}=await supabase.auth.getUser();
  if(userError)return {supabase,org:null,orgs:[],user:null,error:userError.message};
  if(!user)return {supabase,org:null,orgs:[],user:null,error:null as string|null};
  const {data:memberships,error:membershipError}=await supabase.from("organization_members").select("org_id,role,organizations(id,name,base_currency,fy_start_month)").eq("user_id",user.id);
  if(membershipError)return {supabase,org:null,orgs:[],user,error:membershipError.message};
  const rows=(memberships??[]) as unknown as {org_id:string;role:string;organizations:{id:string;name:string;base_currency:string;fy_start_month:number}|null}[];
  const selected=(await cookies()).get("linkora_org")?.value;
  const member=rows.find(m=>m.org_id===selected)??rows[0];
  const orgs=rows.flatMap(m=>m.organizations?[{...m.organizations,role:m.role}]:[]);
  return {supabase,org:member?.organizations?{...member.organizations,role:member.role}:null,orgs,user,error:null as string|null};
});

export type LedgerRow={account_id:string;code:string;account_name:string;entry_id:string;entry_no:string;entry_date:string;description:string;memo:string|null;debit:string;credit:string;running_balance:string;currency:string;exchange_rate:number;transaction_debit:string;transaction_credit:string};
export async function readLedger(supabase:NonNullable<Awaited<ReturnType<typeof createClient>>>,orgId:string,from:string){
  const all:LedgerRow[]=[];
  for(let start=0;;start+=1000){
    const {data,error}=await supabase.from("ledger_exact").select("account_id,code,account_name,entry_id,entry_no,entry_date,description,memo,debit,credit,running_balance,currency,exchange_rate,transaction_debit,transaction_credit").eq("org_id",orgId).gte("entry_date",from).order("entry_date",{ascending:false}).range(start,start+999);
    if(error)return {data:null,error};all.push(...(data??[]) as LedgerRow[]);if((data??[]).length<1000)break;
  }
  return {data:all,error:null};
}

export async function getDashboardData(orgId:string){
  const supabase=await createClient();if(!supabase)return null;
  const today=new Date().toISOString().slice(0,10);const start=new Date();start.setDate(1);start.setMonth(start.getMonth()-11);const from=start.toISOString().slice(0,10);
  const [accountsResult,ledgerResult,entriesResult,approvalsResult,summaryResult,monthlyResult,pnlResult,activityResult]=await Promise.all([
    supabase.from("accounts").select("id,code,name,type,normal_balance,is_active,reporting_class").eq("org_id",orgId).order("code"),
    readLedger(supabase,orgId,from),
    supabase.from("journal_entries").select("id,entry_no,entry_date,description,status,created_by,approved_by").eq("org_id",orgId).order("created_at",{ascending:false}).limit(8),
    supabase.from("journal_entries").select("id,entry_no,entry_date,description,created_by,status").eq("org_id",orgId).in("status",["submitted","pending_approval","approved"]).order("created_at",{ascending:true}).limit(8),
    supabase.rpc("financial_summary_exact",{p_org:orgId,p_from:"0001-01-01",p_to:today,p_as_of:today}),
    supabase.rpc("monthly_financial_activity_exact",{p_org:orgId,p_from:from}),
    supabase.rpc("profit_and_loss_exact",{p_org:orgId,p_from:from,p_to:today}),
    supabase.from("audit_logs").select("id,at,action,entity_type,entity_id").eq("org_id",orgId).order("at",{ascending:false}).limit(6),
  ]);
  const error=accountsResult.error??ledgerResult.error??entriesResult.error??approvalsResult.error??summaryResult.error??monthlyResult.error??pnlResult.error;
  if(error)return {error:error.message,accounts:[],ledger:[],entries:[],approvals:[],activity:[],activityError:activityResult.error?.message??null,metrics:null,monthly:[],breakdown:[]};
  const summary=summaryResult.data?.[0];
  const reportingClasses=new Set((accountsResult.data??[]).flatMap(account=>account.reporting_class?[account.reporting_class]:[]));
  const monthly=(monthlyResult.data??[]).map(r=>({month:new Date(`${r.month_start}T00:00:00`).toLocaleDateString("en-US",{month:"short"}),revenue:Number(r.revenue),expenses:Number(r.expenses),revenueExact:r.revenue,expensesExact:r.expenses}));
  const breakdown=(pnlResult.data??[]).filter(r=>r.type==="expense"&&compareDecimals(r.amount,"0")>0).map(r=>({name:r.name,value:Number(r.amount),amountExact:r.amount})).sort((a,b)=>compareDecimals(b.amountExact,a.amountExact)).slice(0,6);
  return {
    error:null,accounts:accountsResult.data??[],ledger:ledgerResult.data??[],entries:entriesResult.data??[],approvals:approvalsResult.data??[],activity:activityResult.data??[],activityError:activityResult.error?.message??null,
    metrics:summary?{revenue:summary.income,expenses:summary.expenses,profit:summary.profit,cash:reportingClasses.has("cash")?summary.cash_balance:null,bank:reportingClasses.has("bank")?summary.bank_balance:null,assets:summary.assets,liabilities:summary.liabilities,equity:summary.equity,receivable:reportingClasses.has("receivable")?summary.accounts_receivable:null,payable:reportingClasses.has("payable")?summary.accounts_payable:null}:null,
    monthly,breakdown,
  };
}
