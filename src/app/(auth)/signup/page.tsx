import Link from "next/link";
import {AuthForm} from "@/components/auth-form";
import {supabaseConfigured} from "@/lib/supabase/config";

export const metadata={title:"Create account"};
export default function SignupPage(){return <><Link href="/login" className="text-sm text-blue-700">← Back to sign in</Link><h1 className="mt-8 text-3xl font-bold">Create your account</h1><p className="mb-8 mt-2 text-sm text-slate-500">Register through Supabase Auth to set up or join an organization.</p>{!supabaseConfigured&&<div className="mb-5 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">Add the selected project URL and publishable key to <code>.env.local</code> to enable registration.</div>}<AuthForm mode="signup"/></>}
