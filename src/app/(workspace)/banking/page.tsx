import Link from "next/link";
import { getWorkspace } from "@/lib/data";
import { createClient } from "@/lib/supabase/server";
import type { Database } from "@/lib/database.types";
import { BusinessEntryForm } from "@/components/business-entry-form";
import { BankStatementImport } from "@/components/bank-statement-import";
import { BankStatementReconciliation } from "@/components/bank-statement-reconciliation";
import { Card, EmptyState, PageHeader } from "@/components/ui";
import { DataTable } from "@/components/data-table";

export const metadata = { title: "Banking" };
type SupabaseClient=NonNullable<Awaited<ReturnType<typeof createClient>>>;
type StatementRow=Database["public"]["Views"]["bank_statement_rows_exact"]["Row"];
type LedgerCandidate=Database["public"]["Views"]["bank_reconciliation_candidates"]["Row"];
type ReconciliationReport=Database["public"]["Functions"]["bank_reconciliation_report_exact"]["Returns"][number];

export default async function BankingPage() {
  const { org, supabase } = await getWorkspace();
  if (!org || !supabase) return null;
  const [{ data: accounts, error: accountsError }, { data: entries, error }, {data:imports,error:importsError}] = await Promise.all([
    supabase.from("accounts").select("id,code,name,type,reporting_class").eq("org_id", org.id).eq("is_active", true).order("code"),
    supabase.from("journal_entries").select("id,entry_no,entry_date,description,reference,status,entry_kind,created_at").eq("org_id", org.id).in("entry_kind", ["bank_transfer","bank_deposit","bank_withdrawal"]).order("created_at", { ascending: false }),
    supabase.from("bank_statement_imports").select("id,account_id,file_name,statement_start_date,statement_end_date,opening_balance,closing_balance,created_at").eq("org_id",org.id).order("created_at",{ascending:false}).limit(10),
  ]);
  const canCreate = ["owner", "administrator", "accountant", "finance_manager"].includes(org.role);
  const cashBankAccounts=(accounts??[]).filter(a=>a.type==="asset"&&(a.reporting_class==="cash"||a.reporting_class==="bank"));
  const transferRows = (entries ?? []).map(e => ({ ...e, entry_no: e.entry_no ?? "Draft · unnumbered",entry_kind:e.entry_kind.replaceAll("bank_","").replaceAll("_"," ") }));
  const statementImports=imports??[];
  const statementIds=statementImports.map(item=>item.id);
  const statementRowsResult=statementIds.length?await loadStatementRows(supabase,org.id,statementIds):{data:[] as StatementRow[],error:null};
  const statementRows=statementRowsResult.data;
  let ledgerCandidates:LedgerCandidate[]=[];
  let ledgerCandidatesError:string|null=null;
  if(statementRows.length){
    const from=statementRows.reduce((min,row)=>row.transaction_date<min?row.transaction_date:min,statementRows[0].transaction_date);
    const to=statementRows.reduce((max,row)=>row.transaction_date>max?row.transaction_date:max,statementRows[0].transaction_date);
    const accountIds=[...new Set(statementRows.map(row=>row.account_id))];
    const result=await loadLedgerCandidates(supabase,org.id,accountIds,from,to);
    ledgerCandidates=result.data;
    ledgerCandidatesError=result.error;
  }
  const accountById=new Map((accounts??[]).map(account=>[account.id,account.name]));
  const importCards=statementImports.map(item=>({...item,account_name:accountById.get(item.account_id)??"Cash or bank account"}));
  const reportResults=await Promise.all(statementImports.map(async item=>{
    const {data,error}=await supabase.rpc("bank_reconciliation_report_exact",{p_import:item.id});
    return {id:item.id,data:data?.[0]??null,error:error?.message??null};
  }));
  const reconciliationReports=new Map<string,{data:ReconciliationReport|null;error:string|null}>(reportResults.map(result=>[result.id,{data:result.data,error:result.error}]));
  const columns = [
    { key: "entry_no", label: "Entry", render: (r: Record<string, unknown>) => <Link className="font-semibold text-blue-700 hover:underline" href={`/journal-entries/${r.id}`}>{String(r.entry_no)}</Link> },
    { key: "entry_date", label: "Date" },
    { key: "description", label: "Description" },
    { key: "entry_kind", label: "Kind", render:(r:Record<string,unknown>)=><span className="capitalize">{String(r.entry_kind)}</span> },
    { key: "reference", label: "Reference" },
    { key: "status", label: "Workflow", render: (r: Record<string, unknown>) => <span className="capitalize">{String(r.status).replaceAll("_", " ")}</span> },
  ];
  return <><PageHeader eyebrow={org.name} title="Banking" description="Manage cash and bank transfers and reconcile imported statements to posted ledger activity." />
    {canCreate && <div className="mb-6 grid gap-5 xl:grid-cols-2"><Card className="p-5"><h2 className="mb-4 font-semibold">Record deposit</h2>{accountsError?<EmptyState title="Accounts unavailable" description={accountsError.message}/>:cashBankAccounts.length?<BusinessEntryForm orgId={org.id} kind="bank_deposit" accounts={accounts??[]}/>:<EmptyState title="Cash or bank account required" description="Classify an active cash or bank account before recording deposits."/>}</Card><Card className="p-5"><h2 className="mb-4 font-semibold">Record withdrawal</h2>{accountsError?<EmptyState title="Accounts unavailable" description={accountsError.message}/>:cashBankAccounts.length?<BusinessEntryForm orgId={org.id} kind="bank_withdrawal" accounts={accounts??[]}/>:<EmptyState title="Cash or bank account required" description="Classify an active cash or bank account before recording withdrawals."/>}</Card><Card className="p-5 xl:col-span-2"><h2 className="mb-4 font-semibold">Record internal transfer</h2>{accountsError ? <EmptyState title="Accounts unavailable" description={accountsError.message} /> : cashBankAccounts.length >= 2 ? <BusinessEntryForm orgId={org.id} kind="bank_transfer" accounts={cashBankAccounts} /> : <EmptyState title="Two active cash or bank accounts are required" description="Classify at least two active cash or bank accounts in the Chart of Accounts to record an internal transfer." />}</Card></div>}
    <Card className="p-4 md:p-5">{error ? <EmptyState title="Banking activity unavailable" description={error.message} /> : <DataTable rows={transferRows as unknown as Record<string, unknown>[]} columns={columns} empty="No bank deposits, withdrawals, or internal transfers recorded yet." />}</Card>
    <Card className="mt-6 p-5"><h2 className="mb-4 font-semibold">Import a bank statement</h2>{importsError? <EmptyState title="Statement imports unavailable" description={importsError.message}/>:accounts&&accounts.length?canCreate?<BankStatementImport orgId={org.id} accounts={accounts}/>:<EmptyState title="Import permission required" description="Only organization owners, administrators, accountants, and finance managers may import statements."/>:<EmptyState title="No classified accounts" description="Create an active cash or bank account before importing a statement."/>}</Card>
    <Card className="mt-6 p-5">{importsError?<EmptyState title="Statement imports unavailable" description={importsError.message}/>:statementRowsResult.error?<EmptyState title="Statement rows unavailable" description={statementRowsResult.error}/>:ledgerCandidatesError?<EmptyState title="Ledger matches unavailable" description={ledgerCandidatesError}/>:<BankStatementReconciliation imports={importCards} rows={statementRows} ledger={ledgerCandidates} reports={reconciliationReports} currency={org.base_currency}/>}</Card>
    <p className="mt-3 text-xs text-slate-500">Deposits and withdrawals create maker-checker journal drafts using one classified cash/bank account and one offset account. Internal transfers only move between cash/bank accounts and are excluded from income and expenses. CSV reconciliation only links statement rows to exact same-account posted ledger lines. Migration 019 must be applied and tested before these workflows are used.</p></>;
}

async function loadLedgerCandidates(supabase:SupabaseClient,orgId:string,accountIds:string[],from:string,to:string){
  const rows:LedgerCandidate[]=[];
  for(let offset=0;;offset+=1000){
    const {data,error}=await supabase.from("bank_reconciliation_candidates").select("journal_line_id,org_id,account_id,entry_no,entry_date,description,memo,amount,matched_statement_row_id").eq("org_id",orgId).in("account_id",accountIds).gte("entry_date",from).lte("entry_date",to).order("entry_date",{ascending:false}).range(offset,offset+999);
    if(error)return {data:[] as LedgerCandidate[],error:error.message};
    rows.push(...(data??[]) as LedgerCandidate[]);
    if((data??[]).length<1000)break;
  }
  return {data:rows,error:null};
}

async function loadStatementRows(supabase:SupabaseClient,orgId:string,importIds:string[]){
  const rows:StatementRow[]=[];
  for(let offset=0;;offset+=1000){
    const {data,error}=await supabase.from("bank_statement_rows_exact").select("id,org_id,import_id,account_id,row_number,transaction_date,description,reference,amount,matched_journal_line_id,created_at").eq("org_id",orgId).in("import_id",importIds).order("transaction_date",{ascending:false}).order("row_number",{ascending:true}).range(offset,offset+999);
    if(error)return {data:[] as StatementRow[],error:error.message};
    rows.push(...(data??[]) as StatementRow[]);
    if((data??[]).length<1000)break;
  }
  return {data:rows,error:null};
}
