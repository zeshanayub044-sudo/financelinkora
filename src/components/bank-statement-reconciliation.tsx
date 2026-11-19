"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Check, Link2Off } from "lucide-react";
import { Button, Select } from "@/components/ui";
import { matchBankStatementRowAction } from "@/app/(workspace)/actions";
import { formatMoney, negateDecimal, sumDecimals } from "@/lib/utils";
import type { Database } from "@/lib/database.types";

type ReconciliationReport=Database["public"]["Functions"]["bank_reconciliation_report_exact"]["Returns"][number];
type ImportRow={id:string;account_id:string;file_name:string;created_at:string;account_name:string;statement_start_date:string|null;statement_end_date:string|null;opening_balance:number|null;closing_balance:number|null};
type StatementRow={id:string;import_id:string;account_id:string;transaction_date:string;description:string;reference:string|null;amount:string;matched_journal_line_id:string|null};
type LedgerRow={journal_line_id:string;account_id:string;entry_no:string;entry_date:string;description:string;memo:string|null;amount:string;matched_statement_row_id:string|null};
type ReportResult={data:ReconciliationReport|null;error:string|null};

function normalize(value:string){try{return sumDecimals([value]);}catch{return value;}}

export function BankStatementReconciliation({imports,rows,ledger,reports,currency}:{imports:ImportRow[];rows:StatementRow[];ledger:LedgerRow[];reports:Map<string,ReportResult>;currency:string}){
  const router=useRouter();
  const [pendingId,setPendingId]=useState("");
  const [error,setError]=useState("");
  const [notice,setNotice]=useState("");
  const [pages,setPages]=useState<Record<string,number>>({});
  const [pending,startTransition]=useTransition();
  const rowsByImport=useMemo(()=>new Map(imports.map(item=>[item.id,rows.filter(row=>row.import_id===item.id)])),[imports,rows]);
  const ledgerByKey=useMemo(()=>{
    const map=new Map<string,LedgerRow[]>();
    for(const item of ledger){const key=`${item.account_id}:${normalize(item.amount)}`;map.set(key,[...(map.get(key)??[]),item]);}
    return map;
  },[ledger]);

  function match(row:StatementRow,lineId:string|null){
    setPendingId(row.id);setError("");setNotice("");
    startTransition(async()=>{
      try {
        const result=await matchBankStatementRowAction(row.id,lineId);
        if("error" in result&&result.error)setError(result.error);
        else{setNotice("Statement match updated.");router.refresh();}
      } catch {
        setError("Unable to update the statement match because the request failed. Please try again.");
      } finally {
        setPendingId("");
      }
    });
  }

  return <section className="space-y-4">
    <header><h2 className="font-semibold">Statement reconciliation</h2><p className="mt-1 text-xs leading-5 text-slate-500">Match imported rows only to posted ledger lines for the same account and exact signed amount. A ledger line can be matched once. The activity difference is unmatched statement activity minus unmatched posted ledger activity over the import’s date range; it does not represent a closing-balance reconciliation without statement opening and closing balances.</p></header>
    {(error||notice)&&<p role={error?"alert":"status"} className={`text-sm ${error?"text-red-600":"text-emerald-700"}`}>{error||notice}</p>}
    {imports.length===0?<p className="rounded-xl border border-dashed border-border p-8 text-center text-sm text-slate-500">No statement imports yet.</p>:imports.map(statement=>{
      const statementRows=rowsByImport.get(statement.id)??[];
      const matched=statementRows.filter(row=>row.matched_journal_line_id).length;
      const page=pages[statement.id]??1;
      const pageCount=Math.max(1,Math.ceil(statementRows.length/50));
      const visibleRows=statementRows.slice((page-1)*50,page*50);
      const dates=statementRows.map(row=>row.transaction_date).sort();
      const periodLedger=ledger.filter(item=>item.account_id===statement.account_id&&item.entry_date>=(dates[0]??"")&&item.entry_date<=(dates.at(-1)??"")&&item.matched_statement_row_id===null);
      const unmatchedStatement=sumDecimals(statementRows.filter(row=>!row.matched_journal_line_id).map(row=>row.amount));
      const unmatchedLedger=sumDecimals(periodLedger.map(item=>item.amount));
      const reconciliationDifference=sumDecimals([unmatchedStatement,negateDecimal(unmatchedLedger)]);
      const reportResult=reports.get(statement.id);
      const report=reportResult?.data;
      const reportedUnmatchedStatement=report?.unmatched_statement_activity??unmatchedStatement;
      const reportedUnmatchedLedger=report?.unmatched_ledger_activity??unmatchedLedger;
      const reportedActivityDifference=report?.unmatched_activity_difference??reconciliationDifference;
      return <article key={statement.id} className="overflow-hidden rounded-xl border border-border">
        <header className="flex flex-wrap items-center justify-between gap-3 bg-muted/50 px-4 py-3"><div><h3 className="text-sm font-semibold">{statement.file_name}</h3><p className="text-xs text-slate-500">{statement.account_name} · imported {new Date(statement.created_at).toLocaleString()}</p></div><div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs"><span className="font-medium text-slate-600">{matched} of {statementRows.length} matched</span><span>Unmatched statement {formatMoney(reportedUnmatchedStatement,currency)}</span><span>Unmatched ledger {formatMoney(reportedUnmatchedLedger,currency)}</span><span className={reportedActivityDifference==="0"?"font-semibold text-emerald-700":"font-semibold text-amber-700"}>Activity difference {formatMoney(reportedActivityDifference,currency)}</span></div></header>
        <div className="flex flex-wrap items-center gap-x-5 gap-y-2 border-b border-border px-4 py-3 text-xs"><span>Statement period: {statement.statement_start_date??"—"} to {statement.statement_end_date??"—"}</span>{report?<><span>Opening: statement {formatMoney(report.opening_balance,currency)} · ledger {formatMoney(report.ledger_opening_balance,currency)} · difference {formatMoney(report.opening_difference,currency)}</span><span>Closing: statement {formatMoney(report.closing_balance,currency)} · ledger {formatMoney(report.ledger_closing_balance,currency)} · difference {formatMoney(report.closing_difference,currency)}</span><span>Closing vs imported activity: {formatMoney(report.statement_activity_difference,currency)}</span><span className={report.is_reconciled?"font-semibold text-emerald-700":"font-semibold text-amber-700"}>{report.is_reconciled?"Balances reconciled":"Balance differences remain"}</span></>:<span className="text-amber-700">{reportResult?.error??"Opening and closing balances are missing from this import."}</span>}</div>
        {statementRows.length===0?<p className="p-5 text-sm text-slate-500">This import has no rows.</p>:<><div className="divide-y divide-border">{visibleRows.map(row=>{
          const key=`${row.account_id}:${normalize(row.amount)}`;
          const choices=(ledgerByKey.get(key)??[]).filter(item=>item.matched_statement_row_id===null||item.matched_statement_row_id===row.id);
          return <div key={row.id} className="grid gap-3 p-4 md:grid-cols-[minmax(0,1fr)_minmax(240px,1.15fr)_auto] md:items-center">
            <div className="min-w-0"><p className="text-xs text-slate-500">{row.transaction_date}{row.reference?` · ${row.reference}`:""}</p><p className="truncate text-sm font-medium">{row.description}</p><p className="text-sm tabular-nums">{formatMoney(row.amount,currency)}</p></div>
            <Select aria-label={`Match ${row.description} dated ${row.transaction_date}`} value={row.matched_journal_line_id??""} disabled={pending&&pendingId===row.id} onChange={event=>match(row,event.target.value||null)}>
              <option value="">{choices.length?"Select exact ledger match":"No exact unmatched ledger line"}</option>
              {choices.map(item=><option key={item.journal_line_id} value={item.journal_line_id}>{item.entry_no} · {item.entry_date} · {item.description} · {formatMoney(item.amount,currency)}</option>)}
            </Select>
            {row.matched_journal_line_id?<Button variant="secondary" disabled={pending&&pendingId===row.id} onClick={()=>match(row,null)}><Link2Off size={14}/>Unmatch</Button>:<span className="inline-flex items-center gap-1 text-xs text-amber-700"><Check size={14}/>Unmatched</span>}
          </div>;
        })}</div>{pageCount>1&&<footer className="flex items-center justify-between border-t border-border px-4 py-3 text-xs text-slate-500"><span>Rows {(page-1)*50+1}–{Math.min(page*50,statementRows.length)} of {statementRows.length}</span><div className="flex gap-2"><Button variant="secondary" disabled={page<=1} onClick={()=>setPages(value=>({...value,[statement.id]:page-1}))}>Previous</Button><span className="self-center">Page {page} of {pageCount}</span><Button variant="secondary" disabled={page>=pageCount} onClick={()=>setPages(value=>({...value,[statement.id]:page+1}))}>Next</Button></div></footer>}</>}
      </article>;
    })}
  </section>;
}
