"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Plus, Trash2 } from "lucide-react";
import { approveBudgetAction, createBudgetAction, updateBudgetAction } from "@/app/(workspace)/actions";
import { Button, Input, Label, Select } from "@/components/ui";
import { budgetDraftSchema } from "@/lib/validation";

type Account={id:string;code:string;name:string;type:"revenue"|"expense"};
type Line={account_id:string;period_start:string;amount:string};
export type BudgetDraft={id:string;name:string;start_date:string;end_date:string;lines:Line[]};

function fiscalDates(startMonth:number){
  const today=new Date();const month=today.getUTCMonth()+1;const year=today.getUTCFullYear()-(month<startMonth?1:0);
  const start=`${year}-${String(startMonth).padStart(2,"0")}-01`;
  const end=new Date(Date.UTC(year,startMonth-1+12,0)).toISOString().slice(0,10);
  return {start,end};
}

export function BudgetForm({orgId,baseCurrency,fyStartMonth,accounts,initial}:{orgId:string;baseCurrency:string;fyStartMonth:number;accounts:Account[];initial?:BudgetDraft}){
  const router=useRouter();const defaults=fiscalDates(fyStartMonth);
  const [name,setName]=useState(initial?.name??`Financial year budget`);
  const [start,setStart]=useState(initial?.start_date??defaults.start);
  const [end,setEnd]=useState(initial?.end_date??defaults.end);
  const [lines,setLines]=useState<Line[]>(initial?.lines.length?initial.lines:[{account_id:"",period_start:(initial?.start_date??defaults.start).slice(0,7),amount:""}]);
  const [error,setError]=useState("");const [busy,setBusy]=useState(false);
  function patchLine(index:number,patch:Partial<Line>){setLines(current=>current.map((line,i)=>i===index?{...line,...patch}:line));}
  async function submit(event:React.FormEvent){
    event.preventDefault();setError("");
    const input={org_id:orgId,name,start_date:start,end_date:end,lines:lines.map(line=>({...line,period_start:`${line.period_start}-01`}))};
    const parsed=budgetDraftSchema.safeParse(input);
    if(!parsed.success){setError(parsed.error.issues[0]?.message??"Check the budget details.");return;}
    setBusy(true);
    try{
      const result=initial?await updateBudgetAction(initial.id,parsed.data):await createBudgetAction(parsed.data);
      if("error" in result&&result.error){setError(result.error);setBusy(false);return;}
      if("id" in result&&result.id)router.push(`/budgets?budget=${result.id}`);else router.refresh();
    }catch(cause){setError(cause instanceof Error?cause.message:"Unable to save this budget.");}
    setBusy(false);
  }
  return <form onSubmit={submit} className="grid gap-4">
    <div><Label htmlFor="budget-name">Budget name</Label><Input id="budget-name" value={name} maxLength={150} required onChange={e=>setName(e.target.value)}/></div>
    <div className="grid gap-3 sm:grid-cols-2"><div><Label htmlFor="budget-start">Start date</Label><Input id="budget-start" type="date" value={start} required onChange={e=>setStart(e.target.value)}/></div><div><Label htmlFor="budget-end">End date</Label><Input id="budget-end" type="date" value={end} required onChange={e=>setEnd(e.target.value)}/></div></div>
    <div><div className="mb-2 flex items-center justify-between"><div><h3 className="text-sm font-semibold">Monthly account targets</h3><p className="text-xs text-slate-500">Amounts are in {baseCurrency}; actuals come from posted ledger entries.</p></div><Button type="button" variant="secondary" onClick={()=>setLines(current=>[...current,{account_id:"",period_start:start.slice(0,7),amount:""}])}><Plus size={14}/>Add line</Button></div>
      <div className="space-y-2">{lines.map((line,index)=><div key={index} className="grid gap-2 rounded-lg border border-border p-3 sm:grid-cols-[minmax(180px,1fr)_150px_160px_auto]">
        <div><Label htmlFor={`budget-account-${index}`}>Revenue or expense account</Label><Select id={`budget-account-${index}`} required value={line.account_id} onChange={e=>patchLine(index,{account_id:e.target.value})}><option value="">Choose account</option>{accounts.map(account=><option key={account.id} value={account.id}>{account.code} · {account.name} ({account.type})</option>)}</Select></div>
        <div><Label htmlFor={`budget-month-${index}`}>Month</Label><Input id={`budget-month-${index}`} type="month" required value={line.period_start} onChange={e=>patchLine(index,{period_start:e.target.value})}/></div>
        <div><Label htmlFor={`budget-amount-${index}`}>Budget amount</Label><Input id={`budget-amount-${index}`} inputMode="decimal" placeholder="0.00" required value={line.amount} onChange={e=>patchLine(index,{amount:e.target.value})}/></div>
        <Button type="button" variant="ghost" aria-label={`Remove budget line ${index+1}`} disabled={lines.length===1} onClick={()=>setLines(current=>current.filter((_,i)=>i!==index))}><Trash2 size={16}/></Button>
      </div>)}</div>
    </div>
    {error&&<p role="alert" className="text-sm text-red-600">{error}</p>}
    <div className="flex justify-end"><Button disabled={busy||accounts.length===0}>{busy?"Saving…":initial?"Save draft changes":"Save budget draft"}</Button></div>
  </form>;
}

export function BudgetApprovalButton({id}:{id:string}){
  const router=useRouter();const [error,setError]=useState("");const [busy,setBusy]=useState(false);
  return <div className="flex items-center gap-2">{error&&<span role="alert" className="text-xs text-red-600">{error}</span>}<Button disabled={busy} onClick={async()=>{if(!confirm("Approve and lock this budget? The creator cannot approve their own budget."))return;setBusy(true);setError("");try{const result=await approveBudgetAction(id);if(result.error)setError(result.error);else router.refresh();}catch{setError("The approval request failed and its status may be uncertain. Refresh the budget before retrying.");}finally{setBusy(false);}}}>{busy?"Approving…":"Approve budget"}</Button></div>;
}
