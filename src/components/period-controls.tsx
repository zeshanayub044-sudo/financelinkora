"use client";
import Link from "next/link";
import {useState,useTransition} from "react";
import {useRouter} from "next/navigation";
import {Button,Input,Label,Select} from "@/components/ui";
import {createFiscalYearCloseAction,createPeriodAction,setPeriodClosedAction} from "@/app/(workspace)/actions";

export function PeriodCreate({orgId}:{orgId:string}){
  const [open,setOpen]=useState(false),[error,setError]=useState(""),[busy,setBusy]=useState(false);
  return <>{!open?<Button onClick={()=>setOpen(true)}>Add period</Button>:<form className="surface mb-5 flex flex-wrap items-end gap-3 p-4" onSubmit={async e=>{e.preventDefault();setBusy(true);setError("");const f=new FormData(e.currentTarget);try{const result=await createPeriodAction({org_id:orgId,start_date:String(f.get("start")??""),end_date:String(f.get("end")??"")});if(result.error)setError(result.error);else location.reload();}catch{setError("The period request failed. Refresh the period list before retrying.");}finally{setBusy(false);}}}><div><Label htmlFor="start">Start date</Label><Input id="start" name="start" type="date" required/></div><div><Label htmlFor="end">End date</Label><Input id="end" name="end" type="date" required/></div><Button disabled={busy}>Create period</Button><Button type="button" variant="secondary" onClick={()=>setOpen(false)}>Cancel</Button>{error&&<p role="alert" className="basis-full text-xs text-red-600">{error}</p>}</form>}</>;
}

export function PeriodToggle({id,closed}:{id:string;closed:boolean}){
  const [error,setError]=useState("");
  const [busy,setBusy]=useState(false);
  return <div className="text-right"><Button disabled={busy} variant={closed?"secondary":"danger"} onClick={async()=>{if(!confirm(`${closed?"Reopen":"Close"} this period? The database blocks posting in closed periods.`))return;setBusy(true);setError("");try{const result=await setPeriodClosedAction(id,!closed);if(result.error)setError(result.error);else location.reload();}catch{setError("The period request failed. Refresh the period list before retrying.");}finally{setBusy(false);}}}>{busy?"Saving…":closed?"Reopen period":"Close period"}</Button>{error&&<p className="mt-1 text-xs text-red-600">{error}</p>}</div>;
}

type Closing={id:string;journal_entry_id:string;status:"submitted"|"posted"|"reversed"|"voided"};
type EquityAccount={id:string;code:string;name:string};
export function FiscalYearCloseControl({orgId,periodId,periodLabel,closed,closing,accounts}:{orgId:string;periodId:string;periodLabel:string;closed:boolean;closing?:Closing;accounts:EquityAccount[]}){
  const [error,setError]=useState(""),[busy,start]=useTransition(),router=useRouter();
  if(closing?.status==="posted")return <div className="text-right"><span className="mr-2 text-xs font-semibold text-green-700">Year closed</span><Link className="text-xs font-semibold text-blue-700 underline" href={`/journal-entries/${closing.journal_entry_id}`}>Closing journal</Link></div>;
  if(closing?.status==="submitted")return <div className="text-right"><span className="mr-2 text-xs text-amber-700">Awaiting approval</span><Link className="text-xs font-semibold text-blue-700 underline" href={`/journal-entries/${closing.journal_entry_id}`}>Review journal</Link></div>;
  if(closed)return <PeriodToggle id={periodId} closed/>;
  return <form className="flex min-w-60 flex-col items-end gap-2" onSubmit={e=>{e.preventDefault();const f=new FormData(e.currentTarget);start(async()=>{try{setError("");const result=await createFiscalYearCloseAction({org_id:orgId,period_id:periodId,retained_earnings_account_id:f.get("retained_account")});if(result.error){setError(result.error);return}router.push(`/journal-entries/${result.id}`);router.refresh()}catch{setError("The year-close request failed and its result may be uncertain. Check journal drafts before retrying.")}})}}>
    <label className="w-full"><span className="mb-1 block text-[10px] font-semibold text-slate-500">Retained earnings account</span><Select name="retained_account" required defaultValue=""><option value="" disabled>Select equity account…</option>{accounts.map(a=><option key={a.id} value={a.id}>{a.code} · {a.name}</option>)}</Select></label>
    <Button disabled={busy||accounts.length===0}>{busy?"Preparing close…":`Prepare ${periodLabel} close`}</Button>
    <p className="max-w-64 text-right text-[10px] leading-4 text-slate-500">Creates the year-end journal for review. The period locks after the approved journal posts.</p>
    {error&&<p role="alert" className="text-right text-xs text-red-600">{error}</p>}
  </form>;
}
