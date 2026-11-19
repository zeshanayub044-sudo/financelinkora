"use client";
import {useState} from "react";
import {useRouter} from "next/navigation";
import {Select} from "@/components/ui";
import {updateAccountCashFlowClassAction} from "@/app/(workspace)/actions";
type FlowClass="operating"|"investing"|"financing"|"unclassified";
export function AccountCashFlowClass({orgId,accountId,value,reportingClass,canEdit}:{orgId:string;accountId:string;value:FlowClass;reportingClass:string|null;canEdit:boolean}){
 const router=useRouter();const [current,setCurrent]=useState<FlowClass>(value);const [error,setError]=useState("");const [busy,setBusy]=useState(false);
 if(reportingClass==="cash"||reportingClass==="bank")return <span className="text-slate-500">Cash and cash equivalents</span>;
 if(!canEdit)return <span className="capitalize text-slate-500">{value.replaceAll("_"," ")}</span>;
 return <div><Select aria-label={`Cash-flow classification for account ${accountId}`} value={current} disabled={busy} onChange={async event=>{
  const next=event.target.value as FlowClass;setError("");setCurrent(next);setBusy(true);
  try{const result=await updateAccountCashFlowClassAction({org_id:orgId,account_id:accountId,cash_flow_class:next});
   if(result.error){setCurrent(value);setError(result.error);}else router.refresh();
  }catch{setError("The update request failed. Refresh the account list before retrying.");router.refresh();}finally{setBusy(false);}
 }}><option value="unclassified">Unclassified</option><option value="operating">Operating</option><option value="investing">Investing</option><option value="financing">Financing</option></Select>{error&&<span role="alert" className="block max-w-48 text-[10px] text-red-600">{error}</span>}</div>;
}
