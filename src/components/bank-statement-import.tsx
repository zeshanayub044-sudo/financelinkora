"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { FileUp } from "lucide-react";
import { Button, Input, Label, Select } from "@/components/ui";
import { importBankStatementAction } from "@/app/(workspace)/actions";
import { parseBankStatementCsv, type BankStatementCsvRow } from "@/lib/bank-statement-csv";

type Account={id:string;code:string;name:string};
export function BankStatementImport({orgId,accounts}:{orgId:string;accounts:Account[]}){
  const router=useRouter();
  const [file,setFile]=useState<File|null>(null);
  const [accountId,setAccountId]=useState("");
  const [startDate,setStartDate]=useState("");
  const [endDate,setEndDate]=useState("");
  const [openingBalance,setOpeningBalance]=useState("");
  const [closingBalance,setClosingBalance]=useState("");
  const [rows,setRows]=useState<BankStatementCsvRow[]>([]);
  const [error,setError]=useState("");
  const [notice,setNotice]=useState("");
  const [pending,startTransition]=useTransition();

  async function chooseFile(next:File|undefined){
    setFile(next??null);setRows([]);setNotice("");setError("");
    if(!next)return;
    if(!next.name.toLowerCase().endsWith(".csv")){setError("Choose a CSV file.");return;}
    try{const parsed=parseBankStatementCsv(await next.text());setRows(parsed);setNotice(`${parsed.length} statement rows are ready to import.`);}
    catch(e){setError(e instanceof Error?e.message:"Unable to read this CSV file.");}
  }

  function submit(event:React.FormEvent<HTMLFormElement>){
    event.preventDefault();setError("");setNotice("");
    if(!file||!accountId||rows.length===0||!startDate||!endDate||!openingBalance||!closingBalance){setError("Choose an account, statement date range, opening and closing balances, and a valid statement CSV.");return;}
    startTransition(async()=>{
      try {
        const result=await importBankStatementAction({org_id:orgId,account_id:accountId,file_name:file.name,start_date:startDate,end_date:endDate,opening_balance:openingBalance,closing_balance:closingBalance,rows});
        if("error" in result&&result.error){setError(result.error);return;}
        setNotice(`Imported ${rows.length} statement rows. Match them to posted ledger activity below.`);
        setRows([]);setFile(null);const picker=document.getElementById("bank-statement-file");if(picker instanceof HTMLInputElement)picker.value="";
        router.refresh();
      } catch {
        setError("Unable to import the statement because the request failed. Your file and preview are still available; please try again.");
      }
    });
  }

  return <form onSubmit={submit} className="grid gap-4 md:grid-cols-3">
    <div><Label htmlFor="bank-statement-account">Cash or bank account</Label><Select id="bank-statement-account" required value={accountId} onChange={e=>setAccountId(e.target.value)}><option value="">Select account</option>{accounts.map(a=><option key={a.id} value={a.id}>{a.code} · {a.name}</option>)}</Select></div>
    <div><Label htmlFor="statement-start-date">Statement start</Label><Input id="statement-start-date" type="date" required value={startDate} onChange={e=>setStartDate(e.target.value)}/></div>
    <div><Label htmlFor="statement-end-date">Statement end</Label><Input id="statement-end-date" type="date" required value={endDate} onChange={e=>setEndDate(e.target.value)}/></div>
    <div><Label htmlFor="statement-opening-balance">Opening balance</Label><Input id="statement-opening-balance" required inputMode="decimal" placeholder="0.00" value={openingBalance} onChange={e=>setOpeningBalance(e.target.value)}/></div>
    <div><Label htmlFor="statement-closing-balance">Closing balance</Label><Input id="statement-closing-balance" required inputMode="decimal" placeholder="0.00" value={closingBalance} onChange={e=>setClosingBalance(e.target.value)}/></div>
    <div className="md:col-span-2"><Label htmlFor="bank-statement-file">Statement CSV</Label><Input id="bank-statement-file" type="file" accept=".csv,text/csv" onChange={e=>void chooseFile(e.target.files?.[0])}/><p className="mt-1 text-xs text-slate-500">Headers: date, description, amount; optional reference. Dates use YYYY-MM-DD; rows must be inside this statement period. Amounts are signed from the account’s perspective and balances are in the organization base currency.</p></div>
    <div className="flex items-end"><Button type="submit" disabled={pending||!rows.length||!accountId}><FileUp size={16}/>{pending?"Importing…":"Import statement"}</Button></div>
    {(error||notice)&&<p role={error?"alert":"status"} className={`text-sm md:col-span-3 ${error?"text-red-600":"text-emerald-700"}`}>{error||notice}</p>}
    {rows.length>0&&<div className="overflow-x-auto rounded-lg border border-border p-3 text-xs md:col-span-3"><p className="mb-2 font-semibold">Preview · {file?.name}</p><div className="grid min-w-[500px] grid-cols-[110px_1fr_130px] gap-x-3 gap-y-1">{rows.slice(0,5).map((row,index)=><div key={`${row.date}-${index}`} className="contents"><span>{row.date}</span><span className="truncate">{row.description}</span><span className="text-right tabular-nums">{row.amount}</span></div>)}</div>{rows.length>5&&<p className="mt-2 text-slate-500">and {rows.length-5} more rows</p>}</div>}
  </form>;
}
