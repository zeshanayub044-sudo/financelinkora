import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";

export async function getWorkspace() {
  const supabase=await createClient();if(!supabase)return {supabase:null,org:null,user:null};
  const [{data:{user}},{data:memberships}]=await Promise.all([
    supabase.auth.getUser(),supabase.from("organization_members").select("org_id,role,organizations(id,name,base_currency)"),
  ]);
  const rows=(memberships??[]) as unknown as {org_id:string;role:string;organizations:{id:string;name:string;base_currency:string}|null}[];
  const selected=(await cookies()).get("linkora_org")?.value;
  const member=rows.find(m=>m.org_id===selected)??rows[0];
  return {supabase,org:member?.organizations?{...member.organizations,role:member.role}:null,user};
}

export async function getOrgChoices(){
  const supabase=await createClient();if(!supabase)return [];
  const {data}=await supabase.from("organization_members").select("org_id,organizations(id,name,base_currency)");
  return ((data??[]) as unknown as {organizations:{id:string;name:string;base_currency:string}|null}[]).flatMap(r=>r.organizations?[r.organizations]:[]);
}

export type LedgerRow={account_id:string;code:string;account_name:string;entry_id:string;entry_no:string;entry_date:string;description:string;memo:string|null;debit:number;credit:number;running_balance:number;currency:string;exchange_rate:number;transaction_debit:number;transaction_credit:number};
export async function readLedger(supabase:NonNullable<Awaited<ReturnType<typeof createClient>>>,orgId:string,from:string){
  const all:LedgerRow[]=[];
  for(let start=0;;start+=1000){
    const {data,error}=await supabase.from("ledger").select("account_id,code,account_name,entry_id,entry_no,entry_date,description,memo,debit,credit,running_balance,currency,exchange_rate,transaction_debit,transaction_credit").eq("org_id",orgId).gte("entry_date",from).order("entry_date",{ascending:false}).range(start,start+999);
    if(error)return {data:null,error};all.push(...(data??[]) as LedgerRow[]);if((data??[]).length<1000)break;
  }
  return {data:all,error:null};
}

export async function getDashboardData(orgId:string){
  const supabase=await createClient();if(!supabase)return null;
  const today=new Date().toISOString().slice(0,10);const start=new Date();start.setDate(1);start.setMonth(start.getMonth()-11);const from=start.toISOString().slice(0,10);
  const [accountsResult,ledgerResult,entriesResult,approvalsResult,summaryResult,monthlyResult,pnlResult,activityResult]=await Promise.all([
    supabase.from("accounts").select("id,code,name,type,normal_balance,is_active").eq("org_id",orgId).order("code"),
    readLedger(supabase,orgId,from),
    supabase.from("journal_entries").select("id,entry_no,entry_date,description,status,created_by,approved_by").eq("org_id",orgId).order("created_at",{ascending:false}).limit(8),
    supabase.from("journal_entries").select("id,entry_no,entry_date,description,created_by,status").eq("org_id",orgId).in("status",["submitted","pending_approval","approved"]).order("created_at",{ascending:true}).limit(8),
    supabase.rpc("financial_summary",{p_org:orgId,p_from:from,p_to:today,p_as_of:today}),
    supabase.rpc("monthly_financial_activity",{p_org:orgId,p_from:from}),
    supabase.rpc("profit_and_loss",{p_org:orgId,p_from:from,p_to:today}),
    supabase.from("audit_logs").select("id,at,action,entity_type,entity_id").eq("org_id",orgId).order("at",{ascending:false}).limit(6),
  ]);
  const error=accountsResult.error??ledgerResult.error??entriesResult.error??approvalsResult.error??summaryResult.error??monthlyResult.error??pnlResult.error;
  if(error)return {error:error.message,accounts:[],ledger:[],entries:[],approvals:[],activity:[],activityError:activityResult.error?.message??null,metrics:null,monthly:[],breakdown:[]};
  const summary=summaryResult.data?.[0];
  const monthly=(monthlyResult.data??[]).map(r=>({month:new Date(`${r.month_start}T00:00:00`).toLocaleDateString("en-US",{month:"short"}),revenue:Number(r.revenue),expenses:Number(r.expenses)}));
  const breakdown=(pnlResult.data??[]).filter(r=>r.type==="expense"&&Number(r.amount)>0).map(r=>({name:r.name,value:Number(r.amount)})).sort((a,b)=>b.value-a.value).slice(0,6);
  return {
    error:null,accounts:accountsResult.data??[],ledger:ledgerResult.data??[],entries:entriesResult.data??[],approvals:approvalsResult.data??[],activity:activityResult.data??[],activityError:activityResult.error?.message??null,
    metrics:summary?{revenue:Number(summary.income),expenses:Number(summary.expenses),profit:Number(summary.profit),cash:Number(summary.cash_balance),bank:Number(summary.bank_balance),assets:Number(summary.assets),liabilities:Number(summary.liabilities),equity:Number(summary.equity),receivable:Number(summary.accounts_receivable),payable:Number(summary.accounts_payable)}:null,
    monthly,breakdown,
  };
}

