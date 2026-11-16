"use client";
import { useState } from "react";import {useRouter} from "next/navigation";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { createClient } from "@/lib/supabase/client";
import { Button, Input, Label } from "@/components/ui";
import { authCredentialsSchema,passwordSchema } from "@/lib/validation";
type Values={email?:string;password:string};
export function AuthForm({mode="login"}:{mode?:"login"|"forgot"|"reset"}) {
 const router=useRouter();const [message,setMessage]=useState(""); const [busy,setBusy]=useState(false);
 const {register,handleSubmit,formState:{errors}}=useForm<Values>({resolver:zodResolver(mode==="reset"?passwordSchema:authCredentialsSchema) as never,defaultValues:{email:"",password:""}});
 const submit=handleSubmit(async({email,password})=>{setBusy(true);setMessage("");try{const supabase=createClient();const address=email??"";const secret=password??"";const result=mode==="login"?await supabase.auth.signInWithPassword({email:address,password:secret}):mode==="forgot"?await supabase.auth.resetPasswordForEmail(address,{redirectTo:`${location.origin}/auth/callback?next=/reset-password`}):await supabase.auth.updateUser({password:secret});if(result.error)throw result.error;setMessage(mode==="login"?"Signed in. Opening your workspace…":mode==="forgot"?"If this email belongs to an account, a reset link is on its way.":"Password updated. You can now sign in.");if(mode==="login"){router.push("/dashboard");router.refresh();}}catch(error){setMessage(error instanceof Error?error.message:"Authentication failed. Please try again.");}finally{setBusy(false);}});
 const title=mode==="login"?"Welcome back":mode==="forgot"?"Reset your password":"Choose a new password";
 return <form onSubmit={submit} className="space-y-4">{mode!=="reset"&&<div><Label htmlFor="email">Work email</Label><Input id="email" type="email" autoComplete="email" {...register("email")}/>{errors.email&&<p className="mt-1 text-xs text-red-600">{errors.email.message}</p>}</div>}{mode!=="forgot"&&<div><Label htmlFor="password">{mode==="reset"?"New password":"Password"}</Label><Input id="password" type="password" autoComplete={mode==="login"?"current-password":"new-password"} {...register("password")}/>{errors.password&&<p className="mt-1 text-xs text-red-600">{errors.password.message}</p>}</div>}<Button type="submit" disabled={busy} className="w-full">{busy?"Please wait…":title}</Button>{message&&<p role="status" className="rounded-lg bg-slate-100 p-3 text-sm text-slate-700">{message}</p>}</form>;
}
