import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
export async function getWorkspace() {
  const supabase = await createClient();
  if (!supabase) return { supabase: null, org: null, user: null };
  const [{ data: { user } }, { data: memberships }] = await Promise.all([
    supabase.auth.getUser(), supabase.from("organization_members").select("org_id,role,organizations(id,name,base_currency)")
  ]);
  const memberRows = (memberships ?? []) as unknown as {org_id:string;role:string;organizations:{id:string;name:string;base_currency:string}|null}[];
  const cookieStore = await cookies(); const selected = cookieStore.get("linkora_org")?.value;
  const membership = memberRows.find((m) => m.org_id === selected) ?? memberRows[0];
  return { supabase, org: membership?.organizations ? {...membership.organizations, role:membership.role} : null, user };
}
export async function getOrgChoices() {
  const supabase = await createClient(); if (!supabase) return [];
  const {data} = await supabase.from("organization_members").select("org_id,organizations(id,name,base_currency)");
  return ((data ?? []) as unknown as {organizations:{id:string;name:string;base_currency:string}|null}[]).flatMap((x)=>x.organizations?[x.organizations]:[]);
}
type LedgerRow={account_id:string;code:string;account_name:string;entry_id:string;entry_no:string;entry_date:string;description:string;memo:string|null;debit:number;credit:number;running_balance:number};
export async function readLedger(supabase:NonNullable<Awaited<ReturnType<typeof createClient>>>,orgId:string,from:string){
  const all:LedgerRow[]=[];for(let start=0;;start+=1000){const {data,error}=await supabase.from("ledger").select("account_id,code,account_name,entry_id,entry_no,entry_date,description,memo,debit,credit,running_balance").eq("org_id",orgId).gte("entry_date",from).order("entry_date",{ascending:false}).range(start,start+999);if(error)return {data:null,error};all.push(...(data??[]) as LedgerRow[]);if((data??[]).length<1000)break;}return {data:all,error:null};
}
export async function getDashboardData(orgId:string) {
  const supabase = await createClient(); if (!supabase) return null;
  const today=new Date().toISOString().slice(0,10);const start=new Date();start.setMonth(start.getMonth()-11,1);const from=start.toISOString().slice(0,10);
  const [{data:accounts,error:accountError},{data:ledger,error:ledgerError},{data:entries},{data:approvals},{data:tb,error:tbError},{data:activity,error:activityError}] = await Promise.all([
    supabase.from("accounts").select("id,code,name,type,normal_balance,is_active").eq("org_id",orgId).order("code"),
    readLedger(supabase,orgId,from),
    supabase.from("journal_entries").select("id,entry_no,entry_date,description,status,created_by,approved_by").eq("org_id",orgId).order("created_at",{ascending:false}).limit(8),
    supabase.from("journal_entries").select("id,entry_no,entry_date,description,created_by").eq("org_id",orgId).eq("status","draft").order("created_at",{ascending:true}).limit(8),
    supabase.rpc("trial_balance",{p_org:orgId,p_from:"0001-01-01",p_to:today}),
    supabase.from("audit_logs").select("id,at,action,entity_type,entity_id").eq("org_id",orgId).order("at",{ascending:false}).limit(6)
  ]);
  if(accountError||ledgerError||tbError) return {error:accountError?.message??ledgerError?.message??tbError?.message,accounts:[],ledger:[],entries:[],approvals:[],activity:[],activityError:null,metrics:null,monthly:[],breakdown:[]};
  const accts=(accounts??[]) as {id:string;code:string;name:string;type:string;normal_balance:string;is_active:boolean}[];
  const lines=(ledger??[]) as LedgerRow[];const trial=tb??[];
  const net=(r:{debit:number;credit:number;type:string})=>r.type==="asset"||r.type==="expense"?Number(r.debit)-Number(r.credit):Number(r.credit)-Number(r.debit);
  const sumType=(...types:string[])=>trial.filter(r=>types.includes(r.type)).reduce((s,r)=>s+net(r),0);
  const match=(phrase:string,type:string)=>trial.filter(r=>r.type===type&&r.name.toLowerCase().includes(phrase)).reduce((s,r)=>s+net(r),0);
  const revenue=sumType("revenue"),expenses=sumType("expense"),assets=sumType("asset"),liabilities=sumType("liability"),equity=sumType("equity");
  const monthly=Array.from({length:12},(_,i)=>{const date=new Date();date.setDate(1);date.setMonth(date.getMonth()-11+i);const key=`${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,"0")}`;const rows=lines.filter(r=>r.entry_date.startsWith(key));return {month:date.toLocaleDateString("en-US",{month:"short"}),revenue:rows.reduce((s,r)=>{const a=accts.find(x=>x.id===r.account_id);return s+(a?.type==="revenue"?Number(r.credit)-Number(r.debit):0);},0),expenses:rows.reduce((s,r)=>{const a=accts.find(x=>x.id===r.account_id);return s+(a?.type==="expense"?Number(r.debit)-Number(r.credit):0);},0)};});
  const breakdown=trial.filter(r=>r.type==="expense"&&net(r)>0).map(r=>({name:r.name,value:net(r)})).sort((a,b)=>b.value-a.value).slice(0,6);
  return {error:null,accounts:accts,ledger:lines,entries:entries??[],approvals:approvals??[],activity:activity??[],activityError:activityError?.message??null,metrics:{revenue,expenses,profit:revenue-expenses,cash:match("cash","asset"),bank:match("bank","asset"),assets,liabilities,equity,receivable:match("receivable","asset"),payable:match("payable","liability")},monthly,breakdown};
}
