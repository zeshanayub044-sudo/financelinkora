import Link from "next/link";import { AuthForm } from "@/components/auth-form";
export default function ForgotPage(){return <><Link href="/login" className="text-sm text-blue-700">← Back to sign in</Link><h1 className="mt-8 text-3xl font-bold">Reset your password</h1><p className="mb-8 mt-2 text-sm text-slate-500">We’ll send a secure recovery link to your email.</p><AuthForm mode="forgot"/></>;}
