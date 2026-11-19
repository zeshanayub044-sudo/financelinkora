"use client";
import {useState,useTransition} from "react";
import {useRouter} from "next/navigation";
import {Button} from "@/components/ui";
import {createClient} from "@/lib/supabase/client";
import {createReceiptSignedUrlAction} from "@/app/(workspace)/receipt-actions";

type Receipt={id:string;storage_path:string;original_name:string;mime_type:string;size_bytes:number;created_at:string};
const bucket="linkora-finance-receipts";
const maxBytes=10*1024*1024;
export function ReceiptAttachments({orgId,entryId,items,canUpload}:{orgId:string;entryId:string;items:Receipt[];canUpload:boolean}){
 const [busy,start]=useTransition();const [error,setError]=useState("");const [url,setUrl]=useState("");const router=useRouter();
 function upload(event:React.FormEvent<HTMLFormElement>){event.preventDefault();setError("");const form=event.currentTarget;const file=(new FormData(form).get("receipt")) as File|null;
  if(!file||file.size<1||file.size>maxBytes||!["application/pdf","image/jpeg","image/png"].includes(file.type)){setError("Choose a PDF, JPEG, or PNG receipt up to 10 MB.");return;}
  start(async()=>{const client=createClient();const ext=file.type==="application/pdf"?"pdf":file.type==="image/jpeg"?"jpg":"png";const path=`${orgId}/${entryId}/${crypto.randomUUID()}.${ext}`;
   try{
    const result=await client.storage.from(bucket).upload(path,file,{contentType:file.type,upsert:false});if(result.error){setError(result.error.message);return;}
    const {error:registerError}=await client.rpc("register_receipt_attachment",{p_org:orgId,p_entry:entryId,p_storage_path:path,p_original_name:file.name,p_mime_type:file.type,p_size_bytes:file.size});
    if(registerError){try{await client.storage.from(bucket).remove([path]);}catch{/* The private object remains inaccessible without a valid tenant record. */}setError(registerError.message);return;}
    form.reset();router.refresh();
   }catch{
    setError("The receipt request failed and its final status is uncertain. Refresh the receipt list before retrying; an unregistered upload remains private.");
   }
  });
 }
 function open(id:string){setError("");start(async()=>{try{const result=await createReceiptSignedUrlAction({org_id:orgId,receipt_id:id});if(result.error){setError(result.error);return;}if(!result.url){setError("Unable to create a signed receipt link.");return;}setUrl(result.url);window.open(result.url,"_blank","noopener,noreferrer");}catch{setError("Unable to create a signed receipt link because the request failed. Please try again.");}});}
 return <section className="mt-5 rounded-xl border border-border p-4"><div className="flex flex-wrap items-start justify-between gap-3"><div><h2 className="font-semibold">Receipts</h2><p className="mt-1 text-xs text-slate-500">Private attachments are limited to PDF, JPEG, or PNG files up to 10 MB.</p></div>{canUpload&&<form className="flex flex-wrap items-center gap-2" onSubmit={upload}><label className="sr-only" htmlFor={`receipt-${entryId}`}>Choose receipt</label><input id={`receipt-${entryId}`} name="receipt" type="file" accept="application/pdf,image/jpeg,image/png" required className="max-w-56 text-xs"/><Button disabled={busy}>{busy?"Uploading…":"Upload receipt"}</Button></form>}</div>
  {items.length?<ul className="mt-3 divide-y divide-border">{items.map(item=><li key={item.id} className="flex flex-wrap items-center justify-between gap-3 py-2 text-sm"><span>{item.original_name}<small className="ml-2 text-slate-500">{(item.size_bytes/1024).toFixed(0)} KB · {new Date(item.created_at).toLocaleDateString()}</small></span><Button type="button" variant="secondary" className="min-h-8 px-3 py-1 text-xs" disabled={busy} onClick={()=>open(item.id)}>Open (1 minute)</Button></li>)}</ul>:<p className="mt-4 text-sm text-slate-500">No receipt files attached.</p>}
  {error&&<p role="alert" className="mt-3 text-sm text-red-600">{error}</p>}{url&&<p className="mt-2 text-xs"><a className="text-blue-700 underline" href={url} target="_blank" rel="noreferrer">Open the signed receipt link</a> · This link expires in one minute.</p>}
 </section>;
}
