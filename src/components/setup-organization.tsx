"use client";

import {useState} from "react";
import {createClient} from "@/lib/supabase/client";
import {Button,Input,Label,Select} from "@/components/ui";

async function selectOrganization(orgId:string){
  const form=new FormData();
  form.set("org_id",orgId);
  const response=await fetch("/api/organization",{method:"POST",body:form});
  if(response.ok)return;
  let message="Unable to select the new organization.";
  try{const result=await response.json() as {error?:string};message=result.error??message;}catch{/* Keep the safe fallback for non-JSON errors. */}
  throw new Error(message);
}

export function SetupOrganization({userName}:{userName:string}){
  const [name,setName]=useState("");
  const [owner,setOwner]=useState("");
  const [error,setError]=useState("");
  const [busy,setBusy]=useState(false);
  const [createdOrgId,setCreatedOrgId]=useState("");
  const [creationUncertain,setCreationUncertain]=useState(false);

  async function submit(event:React.FormEvent){
    event.preventDefault();
    setBusy(true);
    setError("");
    let orgId=createdOrgId;
    try{
      if(creationUncertain){
        setError("The earlier create request did not return a result. Reload the page to check whether the organization was created before trying again.");
        return;
      }
      if(!orgId){
        const supabase=createClient();
        const result=await supabase.rpc("create_organization",{
          p_name:name,p_legal:null,p_country:null,p_city:null,p_base_currency:"PKR",
          p_fy_start_month:1,p_method:"accrual",p_owner_name:owner,
        });
        if(result.error){
          setCreationUncertain(true);
          throw new Error("The organization request returned no confirmed result. Reload the page to check whether it was created before retrying.");
        }
        orgId=result.data;
        setCreatedOrgId(orgId);
      }
      await selectOrganization(orgId);
      location.reload();
    }catch(cause){
      setError(cause instanceof Error?cause.message:"Unable to complete organization setup. Reload to check the workspace before retrying.");
    }finally{
      setBusy(false);
    }
  }

  return <main className="grid min-h-screen place-items-center p-6"><form onSubmit={submit} className="surface w-full max-w-xl p-8">
    <p className="text-xs font-bold uppercase tracking-widest text-blue-600">Workspace setup</p>
    <h1 className="mt-3 text-2xl font-bold">Create your organization</h1>
    <p className="mt-2 text-sm text-slate-500">The existing database function creates your organization, owner membership, and starter chart of accounts.</p>
    <div className="mt-6"><Label htmlFor="org">Organization name</Label><Input id="org" required value={name} disabled={Boolean(createdOrgId)||creationUncertain} onChange={e=>setName(e.target.value)}/></div>
    <div className="mt-4"><Label htmlFor="owner">Your name</Label><Input id="owner" required value={owner} disabled={Boolean(createdOrgId)||creationUncertain} onChange={e=>setOwner(e.target.value||userName)} placeholder="Account owner"/></div>
    <div className="mt-4"><Label>Base currency</Label><Select disabled defaultValue="PKR"><option value="PKR">PKR · Pakistani Rupee</option></Select><p className="mt-1 text-xs text-slate-400">PKR is the current setup function&apos;s default recommendation.</p></div>
    {createdOrgId&&<p className="mt-4 text-xs text-slate-500">Organization created. Workspace selection is pending; retrying will not create another organization.</p>}
    {creationUncertain&&<p className="mt-4 text-xs text-amber-700">The create request status is uncertain. Reload this page to check for an existing organization before submitting again.</p>}
    {error&&<p role="alert" className="mt-4 text-sm text-red-600">{error}</p>}
    {creationUncertain?<Button type="button" className="mt-6 w-full" onClick={()=>location.reload()}>Reload workspace</Button>:<Button type="submit" disabled={busy||(!createdOrgId&&(!name||!owner))} className="mt-6 w-full">{busy?"Setting up…":createdOrgId?"Retry workspace selection":"Create organization"}</Button>}
  </form></main>;
}
