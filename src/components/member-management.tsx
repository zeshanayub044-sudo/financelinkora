"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button, Input, Label, Select } from "@/components/ui";
import { addOrganizationMemberAction, removeOrganizationMemberAction, setOrganizationMemberRoleAction } from "@/app/(workspace)/actions";

type Role="owner"|"administrator"|"finance_manager"|"accountant"|"approver"|"auditor"|"viewer"|"employee";
type Member={user_id:string;role:Role};
const roles:Role[]=["owner","administrator","finance_manager","accountant","approver","auditor","viewer","employee"];
const label=(role:Role)=>role.replaceAll("_"," ").replace(/\b\w/g,value=>value.toUpperCase());

export function MemberManagement({orgId,currentRole,currentUserId,members}:{orgId:string;currentRole:string;currentUserId:string;members:Member[]}){
  const router=useRouter();const [userId,setUserId]=useState("");const [newRole,setNewRole]=useState<Role>("accountant");const [busy,setBusy]=useState(false);const [error,setError]=useState("");
  const canManage=["owner","administrator"].includes(currentRole);const owner=currentRole==="owner";
  const allowed=owner?roles:roles.filter(role=>!(["owner","administrator"] as Role[]).includes(role));
  async function add(){setError("");if(!userId.trim()){setError("Enter the existing user’s Supabase Auth UUID.");return;}setBusy(true);try{const result=await addOrganizationMemberAction({org_id:orgId,user_id:userId.trim(),role:newRole});if(result.error)setError(result.error);else{setUserId("");router.refresh();}}catch{setError("The membership request failed and its status may be uncertain. Refresh the member list before retrying.");}finally{setBusy(false);}}
  return <div className="space-y-4">
    {canManage&&<div className="rounded-xl border border-border p-4"><h3 className="font-semibold">Add an existing Auth user</h3><p className="mt-1 text-xs leading-5 text-slate-500">This adds a user who already exists in this Supabase project. It does not send an invitation or create an Auth account.</p><div className="mt-3 grid gap-3 sm:grid-cols-[minmax(220px,1fr)_200px_auto] sm:items-end"><div><Label htmlFor="member-user-id">Supabase user UUID</Label><Input id="member-user-id" value={userId} onChange={e=>setUserId(e.target.value)} placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"/></div><div><Label htmlFor="member-new-role">Organization role</Label><Select id="member-new-role" value={newRole} onChange={e=>setNewRole(e.target.value as Role)}>{allowed.map(role=><option value={role} key={role}>{label(role)}</option>)}</Select></div><Button disabled={busy} onClick={add}>{busy?"Adding…":"Add member"}</Button></div></div>}
    <div className="overflow-x-auto rounded-xl border border-border"><table className="w-full min-w-[600px] text-left text-sm"><thead className="bg-muted/60 text-xs uppercase tracking-wide text-slate-500"><tr><th className="px-4 py-3">User ID</th><th className="px-4 py-3">Role</th><th className="px-4 py-3">Actions</th></tr></thead><tbody>{members.map(member=><MemberRow key={member.user_id} orgId={orgId} member={member} isCurrentUser={member.user_id===currentUserId} canManage={canManage} owner={owner} allowed={allowed}/>)}</tbody></table>{members.length===0&&<p className="p-8 text-center text-sm text-slate-500">No members found.</p>}</div>
    {!canManage&&<p className="text-xs text-slate-400">Membership and roles are managed by an organization owner or administrator.</p>}
    {error&&<p role="alert" className="text-sm text-red-600">{error}</p>}
    <p className="text-xs text-slate-400">Role changes and removals go through database authorization and are recorded in the organization audit log.</p>
  </div>;
}

function MemberRow({orgId,member,isCurrentUser,canManage,owner,allowed}:{orgId:string;member:Member;isCurrentUser:boolean;canManage:boolean;owner:boolean;allowed:Role[]}){
  const router=useRouter();const [role,setRole]=useState<Role>(member.role);const [busy,setBusy]=useState(false);const [error,setError]=useState("");
  const canManageTarget=canManage&&(owner||!(["owner","administrator"] as Role[]).includes(member.role));
  const options=owner?roles:allowed;
  return <tr className="border-t border-border"><td className="px-4 py-3 font-mono text-xs">{member.user_id}{isCurrentUser&&<span className="ml-2 font-sans text-slate-400">(you)</span>}</td><td className="px-4 py-3">{canManageTarget?<Select aria-label={`Role for ${member.user_id}`} value={role} onChange={e=>setRole(e.target.value as Role)}>{options.map(value=><option key={value} value={value}>{label(value)}</option>)}</Select>:<span className="capitalize">{label(member.role)}</span>}</td><td className="px-4 py-3"><div className="flex flex-wrap items-center gap-2">{canManageTarget&&role!==member.role&&<Button variant="secondary" disabled={busy} onClick={async()=>{if(!confirm(`Change this member’s role to ${label(role)}?`)){setRole(member.role);return;}setBusy(true);setError("");try{const result=await setOrganizationMemberRoleAction({org_id:orgId,user_id:member.user_id,role});if(result.error){setError(result.error);setRole(member.role);}else router.refresh();}catch{setError("The role request failed and its status may be uncertain. Refresh the member list before retrying.");}finally{setBusy(false);}}}>Save role</Button>}{canManageTarget&&<Button variant="danger" disabled={busy} onClick={async()=>{if(!confirm("Remove this member from the organization? They will lose access to its financial records."))return;setBusy(true);setError("");try{const result=await removeOrganizationMemberAction(orgId,member.user_id);if(result.error)setError(result.error);else router.refresh();}catch{setError("The removal request failed and its status may be uncertain. Refresh the member list before retrying.");}finally{setBusy(false);}}}>Remove</Button>}{error&&<span role="alert" className="text-xs text-red-600">{error}</span>}</div></td></tr>;
}
