"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Select } from "@/components/ui";
import { updateAccountReportingClassAction } from "@/app/(workspace)/actions";

type Class="cash"|"bank"|"receivable"|"payable"|"accumulated_depreciation";
const choices:Record<string,Class[]>={asset:["cash","bank","receivable","accumulated_depreciation"],liability:["payable"],equity:[],revenue:[],expense:[]};
export function AccountReportingClass({orgId,accountId,type,value,canEdit}:{orgId:string;accountId:string;type:string;value:Class|null;canEdit:boolean}){
  const router=useRouter();const [current,setCurrent]=useState<Class|"">(value??"");const [error,setError]=useState("");const [busy,setBusy]=useState(false);const options=choices[type]??[];
  if(!canEdit||options.length===0)return <span className="capitalize text-slate-500">{value??"—"}</span>;
  return <div><Select aria-label={`Dashboard classification for account ${accountId}`} value={current} disabled={busy} onChange={async event=>{
    const next=event.target.value as Class|"";setError("");setCurrent(next);setBusy(true);
    try{const result=await updateAccountReportingClassAction({org_id:orgId,account_id:accountId,reporting_class:next||null,type:type as "asset"|"liability"|"equity"|"revenue"|"expense"});
      if(result.error){setCurrent(value??"");setError(result.error);}else router.refresh();
    }catch{setError("The update request failed. Refresh the account list before retrying.");router.refresh();}finally{setBusy(false);}
  }}><option value="">Not designated</option>{options.map(option=><option key={option} value={option}>{option==="accumulated_depreciation"?"Accumulated depreciation (contra asset)":option[0].toUpperCase()+option.slice(1)}</option>)}</Select>{error&&<span role="alert" className="block max-w-48 text-[10px] text-red-600">{error}</span>}</div>;
}
