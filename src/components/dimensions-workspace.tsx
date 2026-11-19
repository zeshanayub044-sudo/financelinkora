"use client";
import {useState,useTransition} from "react";
import {useRouter} from "next/navigation";
import {Button,Input,Label,Select} from "@/components/ui";
import {createFinancialDimensionAction,setFinancialDimensionActiveAction} from "@/app/(workspace)/actions";

export type DimensionKind="department"|"project";
export type DimensionOption={id:string;code:string;name:string;is_active:boolean};

export function DimensionCreateForm({orgId,kind}:{orgId:string;kind:DimensionKind}){
 const [busy,start]=useTransition();const [message,setMessage]=useState("");const router=useRouter();const label=kind==="department"?"Department":"Project";
 return <form className="grid gap-3 md:grid-cols-2" onSubmit={event=>{event.preventDefault();const form=event.currentTarget;const data=new FormData(form);start(async()=>{try{setMessage("");const result=await createFinancialDimensionAction({kind,org_id:orgId,code:data.get("code"),name:data.get("name"),description:data.get("description"),start_date:data.get("start_date"),end_date:data.get("end_date")});if(result.error){setMessage(result.error);return}form.reset();setMessage(`${label} created.`);router.refresh()}catch{setMessage(`Unable to save this ${label.toLowerCase()} because the request failed. Your entries are still in this form; please try again.`)}})}}>
  <div><Label htmlFor={`${kind}-code`}>Code</Label><Input id={`${kind}-code`} name="code" required maxLength={40} pattern="[A-Za-z0-9][A-Za-z0-9._-]*"/></div>
  <div><Label htmlFor={`${kind}-name`}>Name</Label><Input id={`${kind}-name`} name="name" required minLength={2} maxLength={200}/></div>
  {kind==="project"&&<><div><Label htmlFor="project-start">Start date (optional)</Label><Input id="project-start" name="start_date" type="date"/></div><div><Label htmlFor="project-end">End date (optional)</Label><Input id="project-end" name="end_date" type="date"/></div></>}
  <div className="md:col-span-2"><Label htmlFor={`${kind}-description`}>Description (optional)</Label><Input id={`${kind}-description`} name="description" maxLength={1000}/></div>
  <div className="md:col-span-2 flex flex-wrap items-center gap-3"><Button disabled={busy}>{busy?"Creating…":`Create ${label.toLowerCase()}`}</Button>{message&&<p role={message.endsWith("created.")?"status":"alert"} className="text-sm">{message}</p>}</div>
 </form>;
}

export function DimensionActiveControl({orgId,kind,id,isActive,canManage}:{orgId:string;kind:DimensionKind;id:string;isActive:boolean;canManage:boolean}){
 const [busy,start]=useTransition();const [error,setError]=useState("");const router=useRouter();if(!canManage)return <span className="text-xs text-slate-500">{isActive?"Active":"Inactive"}</span>;
 return <div className="flex items-center gap-2"><span className="text-xs capitalize text-slate-500">{isActive?"Active":"Inactive"}</span><Button className="min-h-8 px-2 py-1 text-xs" variant="secondary" disabled={busy} onClick={()=>{if(!isActive||window.confirm("Deactivate this dimension? Posted history will remain reportable; it will no longer be available on new journal lines."))start(async()=>{try{setError("");const result=await setFinancialDimensionActiveAction({org_id:orgId,kind,id,is_active:!isActive});if(result.error){setError(result.error);return}router.refresh()}catch{setError("The request failed. Please try again.")}})}}>{busy?"Saving…":isActive?"Deactivate":"Reactivate"}</Button>{error&&<span role="alert" className="text-xs text-red-600">{error}</span>}</div>;
}

export function DimensionReportSelector({kind,options,selectedId,from,to}:{kind:DimensionKind;options:DimensionOption[];selectedId:string;from:string;to:string}){
 const router=useRouter();const label=kind==="department"?"Department":"Project";
 return <div className="flex flex-wrap items-end gap-3"><div className="min-w-64"><Label htmlFor={`${kind}-report-select`}>{label} report</Label><Select id={`${kind}-report-select`} value={selectedId} onChange={event=>{const params=new URLSearchParams({from,to});if(event.target.value)params.set(kind,event.target.value);router.push(`/${kind==='department'?'departments':'projects'}?${params.toString()}`)}}><option value="">Choose {label.toLowerCase()}</option>{options.map(option=><option key={option.id} value={option.id}>{option.code} · {option.name}{option.is_active?"":" (inactive)"}</option>)}</Select></div></div>;
}
