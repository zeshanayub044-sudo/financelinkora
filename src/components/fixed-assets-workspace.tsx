"use client";
import {useState,useTransition} from "react";
import {useRouter} from "next/navigation";
import {Button,Input,Label,Select} from "@/components/ui";
import {createFixedAssetDepreciationAction,createFixedAssetDisposalAction,registerFixedAssetAction} from "@/app/(workspace)/actions";

type Account={id:string;code:string;name:string;type:string;reporting_class:string|null;normal_balance:string};
type Entry={id:string;entry_no:string|null;entry_date:string;description:string};
function FormMessage({error,success}:{error:string;success:string}){return <>{error&&<p role="alert" className="text-sm text-red-600">{error}</p>}{success&&<p role="status" className="text-sm text-green-700">{success}</p>}</>}
export function FixedAssetForm({orgId,accounts,entries}:{orgId:string;accounts:Account[];entries:Entry[]}){
 const [busy,start]=useTransition(),[error,setError]=useState(""),[success,setSuccess]=useState(""),router=useRouter();
 const fixed=accounts.filter(a=>a.type==="asset"&&a.reporting_class===null&&a.normal_balance==="debit");
 const accumulated=accounts.filter(a=>a.type==="asset"&&a.reporting_class==="accumulated_depreciation");
 const expense=accounts.filter(a=>a.type==="expense");
 return <form className="grid gap-3 rounded-xl border border-border p-4 md:grid-cols-2" onSubmit={e=>{e.preventDefault();const form=e.currentTarget;const f=new FormData(form);start(async()=>{try{setError("");setSuccess("");const result=await registerFixedAssetAction({org_id:orgId,asset_code:f.get("code"),name:f.get("name"),description:f.get("description"),acquisition_date:f.get("acquisition_date"),in_service_date:f.get("in_service_date"),cost:f.get("cost"),residual_value:f.get("residual_value"),useful_life_months:f.get("life"),asset_account_id:f.get("asset_account"),accumulated_depreciation_account_id:f.get("accumulated_account"),depreciation_expense_account_id:f.get("expense_account"),acquisition_entry_id:f.get("entry")});if(result.error){setError(result.error);return}setSuccess("Asset registered against its posted acquisition journal.");form.reset();router.refresh()}catch{setError("The asset registration request failed and its result may be uncertain. Refresh the register before trying again.")}})}}>
  <div><Label htmlFor="asset-code">Asset code</Label><Input id="asset-code" name="code" required maxLength={40}/></div>
  <div><Label htmlFor="asset-name">Asset name</Label><Input id="asset-name" name="name" required minLength={2} maxLength={200}/></div>
  <div><Label htmlFor="asset-description">Description (optional)</Label><Input id="asset-description" name="description" maxLength={1000}/></div>
  <div><Label htmlFor="asset-entry">Posted acquisition journal</Label><Select id="asset-entry" name="entry" required defaultValue=""><option value="" disabled>Select a posted entry…</option>{entries.map(e=><option key={e.id} value={e.id}>{e.entry_no??e.id.slice(0,8)} · {e.entry_date} · {e.description}</option>)}</Select></div>
  <div><Label htmlFor="asset-date">Acquisition date</Label><Input id="asset-date" name="acquisition_date" type="date" required/></div>
  <div><Label htmlFor="service-date">In-service date</Label><Input id="service-date" name="in_service_date" type="date" required/></div>
  <div><Label htmlFor="asset-cost">Acquisition cost ({"base currency"})</Label><Input id="asset-cost" name="cost" inputMode="decimal" placeholder="0.00" required/></div>
  <div><Label htmlFor="residual">Residual value</Label><Input id="residual" name="residual_value" inputMode="decimal" defaultValue="0" required/></div>
  <div><Label htmlFor="life">Useful life (months)</Label><Input id="life" name="life" type="number" min={1} max={1200} defaultValue={36} required/></div>
  <div><Label htmlFor="asset-account">Fixed asset account</Label><Select id="asset-account" name="asset_account" required defaultValue=""><option value="" disabled>Select…</option>{fixed.map(a=><option key={a.id} value={a.id}>{a.code} · {a.name}</option>)}</Select></div>
  <div><Label htmlFor="accum-account">Accumulated depreciation (contra-asset)</Label><Select id="accum-account" name="accumulated_account" required defaultValue=""><option value="" disabled>Select…</option>{accumulated.map(a=><option key={a.id} value={a.id}>{a.code} · {a.name}</option>)}</Select></div>
  <div><Label htmlFor="dep-expense">Depreciation expense account</Label><Select id="dep-expense" name="expense_account" required defaultValue=""><option value="" disabled>Select…</option>{expense.map(a=><option key={a.id} value={a.id}>{a.code} · {a.name}</option>)}</Select></div>
  <p className="text-xs text-slate-500 md:col-span-2">Registration requires a posted base-currency journal with an exact debit to the selected asset account. Register each asset amount only once against the source journal.</p>
  <FormMessage error={error} success={success}/><div className="md:col-span-2"><Button disabled={busy||entries.length===0||fixed.length===0||accumulated.length===0||expense.length===0}>{busy?"Registering…":"Register asset"}</Button></div>
 </form>;
}
export function DepreciationRunForm({orgId}:{orgId:string}){
 const [busy,start]=useTransition(),[error,setError]=useState(""),router=useRouter();const now=new Date();const last=new Date(now.getFullYear(),now.getMonth()+1,0);const end=`${last.getFullYear()}-${String(last.getMonth()+1).padStart(2,"0")}-${String(last.getDate()).padStart(2,"0")}`;
 return <form className="flex flex-wrap items-end gap-3" onSubmit={e=>{e.preventDefault();const f=new FormData(e.currentTarget);start(async()=>{try{setError("");const result=await createFixedAssetDepreciationAction(orgId,String(f.get("period_end")));if(result.error){setError(result.error);return}router.push(`/journal-entries/${result.id}`);router.refresh()}catch{setError("The depreciation request failed and its result may be uncertain. Check the draft list before trying again.")}})}}>
  <div><Label htmlFor="depreciation-month-end">Depreciation month end</Label><Input id="depreciation-month-end" type="date" name="period_end" required defaultValue={end}/></div>
  <Button disabled={busy}>{busy?"Preparing journal…":"Prepare depreciation journal"}</Button>
  {error&&<p role="alert" className="w-full text-sm text-red-600">{error}</p>}
 </form>;
}

type DisposalAsset={id:string;asset_code:string;name:string;net_book_value:string};
export function compareFixedAssetAmounts(a:string,b:string){const normalize=(value:string)=>{const [rawWhole="0",rawFraction=""]=value.split(".");const whole=rawWhole.replace(/^0+(?=\d)/,"");const fraction=rawFraction.padEnd(4,"0").slice(0,4);return {whole,fraction}};const x=normalize(a),y=normalize(b);return x.whole.length===y.whole.length?(x.whole===y.whole?(x.fraction===y.fraction?0:x.fraction>y.fraction?1:-1):x.whole>y.whole?1:-1):x.whole.length>y.whole.length?1:-1}
export function FixedAssetDisposalForm({orgId,asset,accounts}:{orgId:string;asset:DisposalAsset;accounts:Account[]}){
 const [busy,start]=useTransition(),[error,setError]=useState(""),[proceeds,setProceeds]=useState("0"),router=useRouter();
 const today=new Date(),monthEnd=new Date(today.getFullYear(),today.getMonth()+1,0),defaultDate=`${monthEnd.getFullYear()}-${String(monthEnd.getMonth()+1).padStart(2,"0")}-${String(monthEnd.getDate()).padStart(2,"0")}`;
 const cash=accounts.filter(a=>a.type==="asset"&&(a.reporting_class==="cash"||a.reporting_class==="bank"));
 const revenue=accounts.filter(a=>a.type==="revenue"),expenses=accounts.filter(a=>a.type==="expense");
 const pValid=/^(?:0|[1-9]\d{0,15})(?:\.\d{1,4})?$/.test(proceeds),comparison=pValid?compareFixedAssetAmounts(proceeds,asset.net_book_value):0,gain=comparison>0,loss=comparison<0,hasProceeds=pValid&&compareFixedAssetAmounts(proceeds,"0")>0;
 return <form className="grid gap-2 rounded-lg border border-border bg-muted/30 p-3 md:grid-cols-2" onSubmit={e=>{e.preventDefault();const f=new FormData(e.currentTarget);start(async()=>{try{setError("");const result=await createFixedAssetDisposalAction({org_id:orgId,asset_id:asset.id,disposal_date:f.get("date"),proceeds,proceeds_account_id:hasProceeds?f.get("cash"):null,gain_account_id:gain?f.get("gain"):null,loss_account_id:loss?f.get("loss"):null});if(result.error){setError(result.error);return}router.push(`/journal-entries/${result.id}`);router.refresh()}catch{setError("The disposal request failed and its result may be uncertain. Check journal drafts before trying again.")}})}}>
  <p className="text-sm font-medium md:col-span-2">Dispose {asset.asset_code} · {asset.name} · carrying value {asset.net_book_value}</p>
  <div><Label htmlFor={`dispose-date-${asset.id}`}>Disposal date (month end)</Label><Input id={`dispose-date-${asset.id}`} name="date" type="date" required defaultValue={defaultDate}/></div>
  <div><Label htmlFor={`dispose-proceeds-${asset.id}`}>Proceeds</Label><Input id={`dispose-proceeds-${asset.id}`} name="proceeds" inputMode="decimal" value={proceeds} onChange={e=>setProceeds(e.target.value)} required/></div>
  {hasProceeds&&<div><Label htmlFor={`dispose-cash-${asset.id}`}>Receiving cash/bank account</Label><Select id={`dispose-cash-${asset.id}`} name="cash" required defaultValue=""><option value="" disabled>Select…</option>{cash.map(a=><option key={a.id} value={a.id}>{a.code} · {a.name}</option>)}</Select></div>}
  {gain&&<div><Label htmlFor={`dispose-gain-${asset.id}`}>Gain account</Label><Select id={`dispose-gain-${asset.id}`} name="gain" required defaultValue=""><option value="" disabled>Select…</option>{revenue.map(a=><option key={a.id} value={a.id}>{a.code} · {a.name}</option>)}</Select></div>}
  {loss&&<div><Label htmlFor={`dispose-loss-${asset.id}`}>Loss account</Label><Select id={`dispose-loss-${asset.id}`} name="loss" required defaultValue=""><option value="" disabled>Select…</option>{expenses.map(a=><option key={a.id} value={a.id}>{a.code} · {a.name}</option>)}</Select></div>}
  <p className="text-xs text-muted-foreground md:col-span-2">Creates a balanced disposal journal for approval. Depreciation through the disposal date must already be posted. The asset remains active until the disposal journal posts.</p>
  {error&&<p role="alert" className="text-sm text-red-600 md:col-span-2">{error}</p>}
  <div className="md:col-span-2"><Button disabled={busy||!pValid||(hasProceeds&&cash.length===0)||(gain&&revenue.length===0)||(loss&&expenses.length===0)}>{busy?"Submitting…":"Submit disposal for approval"}</Button></div>
 </form>;
}
