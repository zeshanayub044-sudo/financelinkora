"use client";
import {useState,useTransition} from "react";
import {useRouter} from "next/navigation";
import {Button,Input,Label,Select} from "@/components/ui";
import {DataTable} from "@/components/data-table";
import {CsvExport} from "@/components/csv-export";
import {formatMoney} from "@/lib/utils";
import {createTaxCodeAction,setTaxCodeActiveAction} from "@/app/(workspace)/actions";

export type TaxCode={id:string;code:string;name:string;scope:"sales"|"purchases"|"both";rate:string;sales_account_id:string|null;purchase_account_id:string|null;effective_from:string;effective_to:string|null;is_active:boolean};
type Account={id:string;code:string;name:string;type:string};

export function TaxCodeForm({orgId,accounts}:{orgId:string;accounts:Account[]}){
  const [busy,start]=useTransition();const [error,setError]=useState("");const [saved,setSaved]=useState(false);const [scope,setScope]=useState<"sales"|"purchases"|"both">("both");const [rate,setRate]=useState("");const router=useRouter();
  const liabilities=accounts.filter(a=>a.type==="liability");const assets=accounts.filter(a=>a.type==="asset");
  return <form className="grid gap-3 md:grid-cols-2" onSubmit={event=>{event.preventDefault();const form=event.currentTarget;const values=new FormData(form);start(async()=>{try{setError("");setSaved(false);const result=await createTaxCodeAction({org_id:orgId,code:values.get("code"),name:values.get("name"),scope:values.get("scope"),rate:values.get("rate"),sales_account_id:values.get("sales_account_id"),purchase_account_id:values.get("purchase_account_id"),effective_from:values.get("effective_from"),effective_to:values.get("effective_to")});if("error" in result){setError(result.error??"Unable to save tax code.");return}form.reset();setScope("both");setRate("");setSaved(true);router.refresh()}catch{setError("Unable to save this tax code because the request failed. Your entries are still in this form; please try again.")}})}}>
    <div><Label htmlFor="tax-code">Code</Label><Input id="tax-code" name="code" required maxLength={40} placeholder="VAT-STD"/></div>
    <div><Label htmlFor="tax-name">Name</Label><Input id="tax-name" name="name" required minLength={2} maxLength={200} placeholder="Standard VAT"/></div>
    <div><Label htmlFor="tax-scope">Applies to</Label><Select id="tax-scope" name="scope" value={scope} onChange={e=>setScope(e.target.value as typeof scope)}><option value="sales">Sales</option><option value="purchases">Purchases</option><option value="both">Sales and purchases</option></Select></div>
    <div><Label htmlFor="tax-rate">Rate (%)</Label><Input id="tax-rate" name="rate" type="number" inputMode="decimal" min="0" max="100" step="0.000001" required maxLength={12} value={rate} onChange={e=>setRate(e.target.value)} placeholder="Enter your approved rate"/><p className="mt-1 text-[11px] text-slate-500">Six decimal places maximum; no legal rate is prefilled.</p></div>
    <div><Label htmlFor="tax-sales-account">Sales tax liability account</Label><Select id="tax-sales-account" name="sales_account_id" defaultValue="" required={Number(rate)>0&&(scope==="sales"||scope==="both")}><option value="">Select an account…</option>{liabilities.map(a=><option key={a.id} value={a.id}>{a.code} · {a.name}</option>)}</Select></div>
    <div><Label htmlFor="tax-purchase-account">Recoverable purchase tax asset</Label><Select id="tax-purchase-account" name="purchase_account_id" defaultValue="" required={Number(rate)>0&&(scope==="purchases"||scope==="both")}><option value="">Select an account…</option>{assets.map(a=><option key={a.id} value={a.id}>{a.code} · {a.name}</option>)}</Select></div>
    <div><Label htmlFor="tax-effective-from">Effective from</Label><Input id="tax-effective-from" name="effective_from" type="date" required defaultValue={new Date().toISOString().slice(0,10)}/></div>
    <div><Label htmlFor="tax-effective-to">Effective through (optional)</Label><Input id="tax-effective-to" name="effective_to" type="date"/></div>
    <p className="text-xs leading-5 text-slate-500 md:col-span-2">Rates and accounts cannot be edited after creation. Create a new code for a new policy or effective date. Tax is calculated on top of the line amount and is snapshotted into invoice or bill drafts.</p>
    {error&&<p className="text-sm text-red-600 md:col-span-2" role="alert">{error}</p>}{saved&&<p className="text-sm text-green-700 md:col-span-2" role="status">Tax code saved.</p>}
    <div className="md:col-span-2"><Button disabled={busy||accounts.length===0}>{busy?"Saving…":"Create tax code"}</Button></div>
  </form>;
}

export function TaxCodeTable({orgId,codes,currency,canManage,accounts}:{orgId:string;codes:TaxCode[];currency:string;canManage:boolean;accounts:Account[]}){
  const [busy,start]=useTransition();const [error,setError]=useState("");const router=useRouter();
  const accountName=(id:string|null)=>{const account=accounts.find(a=>a.id===id);return account?`${account.code} · ${account.name}`:"—"};
  const rows=codes.map(code=>({...code,rate_display:`${code.rate}%`,status:code.is_active?"Active":"Inactive",accounts:`Sales: ${accountName(code.sales_account_id)} · Purchases: ${accountName(code.purchase_account_id)}`,action:<Button variant="secondary" disabled={!canManage||busy} onClick={()=>{if(code.is_active&&!window.confirm(`Deactivate ${code.code}? Existing posted entries and saved tax amounts remain unchanged.`))return;start(async()=>{try{setError("");const result=await setTaxCodeActiveAction({org_id:orgId,tax_code_id:code.id,is_active:!code.is_active});if("error"in result){setError(result.error??"Unable to update tax code.");return}router.refresh()}catch{setError("Unable to update the tax code because the request failed. Please try again.")}})}}>{code.is_active?"Deactivate":"Activate"}</Button>}));
  return <><DataTable rows={rows as unknown as Record<string,unknown>[]} columns={[{key:"code",label:"Code"},{key:"name",label:"Tax"},{key:"scope",label:"Scope",render:r=>String(r.scope).replace("purchases","Purchases").replace("sales","Sales").replace("both","Sales & purchases")},{key:"rate_display",label:"Rate"},{key:"accounts",label:"Accounts"},{key:"effective_from",label:"From"},{key:"effective_to",label:"Through"},{key:"status",label:"Status"},{key:"action",label:"Action",render:r=>r.action as React.ReactNode}]} empty="No tax codes configured. Rates must be entered from an approved organization policy."/>
   {error&&<p className="mt-3 text-sm text-red-600" role="alert">{error}</p>}
   <p className="mt-3 text-xs text-slate-500">Account references are tenant-scoped. For financial documents, tax amount is rounded to four decimal places before posting in {currency}.</p>
  </>;
}

export type TaxActivity={tax_code_id:string;code:string;name:string;rate:string;sales_tax:string;purchase_tax:string;net_tax:string};
export function TaxActivityTable({rows,currency,from,to}:{rows:TaxActivity[];currency:string;from:string;to:string}){
  const csv=rows.map(r=>[r.code,r.name,r.rate,r.sales_tax,r.purchase_tax,r.net_tax]);
  return <><div className="mb-3 flex justify-end"><CsvExport filename={`tax-activity-${from}-${to}.csv`} headers={["Code","Tax","Rate","Sales tax","Purchase tax","Net tax movement"]} rows={csv}/></div><DataTable rows={rows.map(r=>({...r,sales_display:formatMoney(r.sales_tax,currency),purchase_display:formatMoney(r.purchase_tax,currency),net_display:formatMoney(r.net_tax,currency)})) as unknown as Record<string,unknown>[]} columns={[{key:"code",label:"Code"},{key:"name",label:"Tax"},{key:"rate",label:"Rate",render:r=>`${String(r.rate)}%`},{key:"sales_display",label:"Sales tax"},{key:"purchase_display",label:"Recoverable purchase tax"},{key:"net_display",label:"Net movement"}]} empty="No posted tax activity was recorded for this period."/></>;
}
