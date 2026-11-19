"use client";

import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Check, RotateCcw, Send, X } from "lucide-react";
import { Button, Input, Label } from "@/components/ui";
import { approveAction, postAction, queueAction, rejectAction, reverseAction, submitAction } from "@/app/(workspace)/actions";

type Result = { error?: string; ok?: boolean; id?: string };
export function EntryActions({ id, status, role="employee", createdBy, currentUserId, balanced=false }:{id:string;status:string;role?:string;createdBy?:string;currentUserId?:string;balanced?:boolean}) {
  const router=useRouter();
  const [busy,setBusy]=useState(false);const [error,setError]=useState("");const [dialog,setDialog]=useState<"reject"|"reverse"|null>(null);
  const [reversalId,setReversalId]=useState("");
  const isMaker=createdBy===currentUserId;
  const canWrite=["owner","administrator","accountant","finance_manager"].includes(role);
  const canReview=["owner","administrator","finance_manager","approver"].includes(role)&&!isMaker;
  async function run(fn:()=>Promise<Result>,confirmText:string){if(!confirm(confirmText))return;setBusy(true);setError("");try{const result=await fn();if(result.error)setError(result.error);else router.refresh();}catch{setError("The journal action could not be completed. Check your connection and current permissions, then try again.");}finally{setBusy(false);}}
  return <div className="flex flex-wrap items-center gap-2">
    {status==="draft"&&isMaker&&canWrite&&<><Link className="inline-flex h-10 items-center rounded-lg border border-border px-4 text-sm font-medium hover:bg-muted" href={`/journal-entries/${id}/edit`}>Edit draft</Link><Button disabled={busy||!balanced} title={!balanced?"Balance the draft before submitting":""} onClick={()=>run(()=>submitAction(id),"Submit this balanced draft for review?")}><Send size={15}/>Submit for review</Button></>}
    {status==="submitted"&&canReview&&<Button variant="secondary" disabled={busy} onClick={()=>run(()=>queueAction(id),"Move this submission into the pending approval queue?")}><Send size={15}/>Queue for approval</Button>}
    {status==="pending_approval"&&canReview&&<>
      <Button disabled={busy} onClick={()=>run(()=>approveAction(id),"Approve this entry? You cannot approve an entry you created.")}><Check size={15}/>Approve</Button>
      <Button variant="secondary" disabled={busy} onClick={()=>setDialog("reject")}><X size={15}/>Reject</Button>
    </>}
    {status==="approved"&&["owner","administrator","accountant","finance_manager"].includes(role)&&<Button disabled={busy} onClick={()=>run(()=>postAction(id),"Post this approved entry? Posting is permanent; corrections require a reversal.")}><Send size={15}/>Post entry</Button>}
    {status==="posted"&&["owner","administrator","accountant","finance_manager"].includes(role)&&<Button variant="secondary" disabled={busy} onClick={()=>setDialog("reverse")}><RotateCcw size={15}/>Create reversal</Button>}
    {reversalId&&<Link className="text-sm font-semibold text-blue-700 underline" href={`/journal-entries/${reversalId}`}>Open reversal draft</Link>}
    {error&&<p role="alert" className="basis-full text-xs text-red-600">{error}</p>}
    {dialog&&<div className="fixed inset-0 z-50 grid place-items-center bg-slate-950/55 p-4"><div role="dialog" aria-modal="true" aria-labelledby="entry-action-title" className="surface w-full max-w-md p-6">
      <h2 id="entry-action-title" className="text-lg font-bold">{dialog==="reject"?"Reject journal entry":"Create reversing entry"}</h2>
      <p className="mt-1 text-sm text-slate-500">{dialog==="reject"?"The entry returns to draft for correction. A rejection reason is recorded in the audit trail.":"A reversing draft is created with opposite debit and credit lines. It must go through review and posting."}</p>
      {dialog==="reverse"&&<div className="mt-4"><Label htmlFor="reverse-date">Reversal date</Label><Input type="date" id="reverse-date" defaultValue={new Date().toISOString().slice(0,10)}/></div>}
      <div className="mt-3"><Label htmlFor="action-reason">{dialog==="reject"?"Rejection reason":"Reversal reason"}</Label><textarea id="action-reason" required rows={3} maxLength={2000} className="mt-1 w-full rounded-lg border border-border bg-background p-3 text-sm" placeholder="Explain the reason"/></div>
      <div className="mt-5 flex justify-end gap-2"><Button variant="secondary" disabled={busy} onClick={()=>setDialog(null)}>Cancel</Button><Button variant={dialog==="reject"?"danger":"primary"} disabled={busy} onClick={async()=>{
        const reason=(document.getElementById("action-reason") as HTMLTextAreaElement).value;
        setBusy(true);setError("");
        try{
          const result=dialog==="reject"?await rejectAction(id,reason):await reverseAction(id,(document.getElementById("reverse-date") as HTMLInputElement).value,reason);
          if(result.error)setError(result.error);else if(dialog==="reverse"&&"id" in result&&result.id)setReversalId(result.id);else router.refresh();
        }catch{setError("The journal action could not be completed. Check your connection and current permissions, then try again.");}
        finally{setDialog(null);setBusy(false);}
      }}>{busy?"Saving…":dialog==="reject"?"Confirm rejection":"Create reversal draft"}</Button></div>
    </div></div>}
  </div>;
}
