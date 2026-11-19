import {getWorkspace} from "@/lib/data";
import {PayrollWorkspace,type PayrollRun} from "@/components/payroll-workspace";
import {Card,EmptyState,PageHeader} from "@/components/ui";

export const metadata={title:"Payroll"};
const payrollRoles=["owner","administrator","finance_manager","accountant","approver","auditor"];
export default async function PayrollPage(){
 const {org,supabase,user}=await getWorkspace();if(!org||!supabase)return null;
 if(!user||!payrollRoles.includes(org.role))return <><PageHeader eyebrow={org.name} title="Payroll" description="Confidential compensation records and payroll journal processing."/><Card><EmptyState title="Payroll access restricted" description="Payroll access is limited to authorized organization finance, approval, and audit roles."/></Card></>;
 const [{data:employees,error:employeeError},{data:components,error:componentError},{data:accounts,error:accountError},{data:runs,error:runError}]=await Promise.all([
  supabase.from("payroll_employees").select("id,employee_code,full_name,start_date,is_active").eq("org_id",org.id).order("employee_code"),
  supabase.from("payroll_components").select("id,code,name,component_type,account_id,is_active").eq("org_id",org.id).order("code"),
  supabase.from("accounts").select("id,code,name,type").eq("org_id",org.id).eq("is_active",true).order("code"),
  supabase.from("payroll_runs").select("id,reference,period_start,period_end,status,journal_entry_id,created_by,created_at").eq("org_id",org.id).order("created_at",{ascending:false}).limit(100),
 ]);
 const error=employeeError??componentError??accountError??runError;
 let runRows:PayrollRun[]=[];
 if(!error&&runs?.length){const ids=runs.map(r=>r.id);const {data:lines,error:lineError}=await supabase.from("payroll_run_lines").select("run_id,employee_id,component_id,employee_code,employee_name,component_code,component_name,component_type,amount").eq("org_id",org.id).in("run_id",ids);if(lineError)return <><PageHeader eyebrow={org.name} title="Payroll"/><Card><EmptyState title="Payroll details unavailable" description={lineError.message}/></Card></>;runRows=runs.map(r=>({...r,lines:(lines??[]).filter(l=>l.run_id===r.id)})) as PayrollRun[];}
 return <><PageHeader eyebrow={org.name} title="Payroll" description="Maintain compensation records and prepare balanced payroll journals for maker-checker review."/>{error?<Card><EmptyState title="Payroll data unavailable" description={error.message}/></Card>:<PayrollWorkspace orgId={org.id} role={org.role} userId={user.id} currency={org.base_currency} employees={(employees??[]) as never} components={(components??[]) as never} accounts={(accounts??[]) as never} runs={runRows}/>}</>;
}
