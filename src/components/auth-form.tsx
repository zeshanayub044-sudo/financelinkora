"use client";
import { useState } from "react";import {useRouter} from "next/navigation";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { createClient } from "@/lib/supabase/client";
import { safeInternalPath } from "@/lib/safe-redirect";
import { Button, Input, Label } from "@/components/ui";
import { authCredentialsSchema,passwordSchema } from "@/lib/validation";
type Values={email?:string;password:string};
export function AuthForm({mode="login",redirectTo="/dashboard"}:{mode?:"login"|"signup"|"forgot"|"reset";redirectTo?:string}) {
 const router=useRouter();const [message,setMessage]=useState(""); const [busy,setBusy]=useState(false);
 const loginDestination=safeInternalPath(redirectTo);
 const {register,handleSubmit,formState:{errors}}=useForm<Values>({resolver:zodResolver(mode==="reset"?passwordSchema:authCredentialsSchema) as never,defaultValues:{email:"",password:""}});
 const submit=handleSubmit(async({email,password})=>{setBusy(true);setMessage("");try{const supabase=createClient();const address=email??"";const secret=password??"";const result=mode==="login"?await supabase.auth.signInWithPassword({email:address,password:secret}):mode==="signup"?await supabase.auth.signUp({email:address,password:secret,options:{emailRedirectTo:`${location.origin}/auth/callback`}}):mode==="forgot"?await supabase.auth.resetPasswordForEmail(address,{redirectTo:`${location.origin}/auth/callback?next=/reset-password`}):await supabase.auth.updateUser({password:secret});if(result.error)throw result.error;if(mode==="login"){setMessage("Signed in. Opening your workspace…");router.push(loginDestination);router.refresh();}else if(mode==="signup"){const session="data" in result&&result.data&&"session" in result.data?result.data.session:null;if(session){setMessage("Account created. Opening your workspace…");router.push("/dashboard");router.refresh();}else setMessage("Account request received. Check your email to confirm the address before signing in.");}else setMessage(mode==="forgot"?"If this email belongs to an account, a reset link is on its way.":"Password updated. You can now sign in.");}catch(error){setMessage(error instanceof Error?error.message:"Authentication failed. Please try again.");}finally{setBusy(false);}});
 const title=mode==="login"?"Welcome back":mode==="signup"?"Create account":mode==="forgot"?"Send recovery link":"Update password";
 return <form onSubmit={submit} className="space-y-4">{mode!=="reset"&&<div><Label htmlFor="email">Work email</Label><Input id="email" type="email" autoComplete="email" {...register("email")}/>{errors.email&&<p className="mt-1 text-xs text-red-600">{errors.email.message}</p>}</div>}{mode!=="forgot"&&<div><Label htmlFor="password">{mode==="reset"?"New password":"Password"}</Label><Input id="password" type="password" autoComplete={mode==="login"?"current-password":"new-password"} {...register("password")}/>{errors.password&&<p className="mt-1 text-xs text-red-600">{errors.password.message}</p>}</div>}<Button type="submit" disabled={busy} className="w-full">{busy?"Please wait…":title}</Button>{message&&<p role="status" className="rounded-lg bg-slate-100 p-3 text-sm text-slate-700">{message}</p>}</form>;
}
