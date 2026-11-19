"use server";
import {z} from "zod";
import {createClient} from "@/lib/supabase/server";

export async function createReceiptSignedUrlAction(input:unknown){
 const parsed=z.object({org_id:z.string().uuid(),receipt_id:z.string().uuid()}).safeParse(input);
 if(!parsed.success)return {error:"Invalid receipt."};
 const supabase=await createClient();if(!supabase)return {error:"Supabase is not configured."};
 const {data:{user},error:authError}=await supabase.auth.getUser();if(authError||!user)return {error:"Sign in to open receipt files."};
 const {data:membership,error:memberError}=await supabase.from("organization_members").select("role").eq("org_id",parsed.data.org_id).eq("user_id",user.id).maybeSingle();
 if(memberError||!membership||!["owner","administrator","finance_manager","accountant","auditor","viewer"].includes(membership.role))return {error:"You are not authorized to read this receipt."};
 const {data:receipt,error}=await supabase.from("receipt_attachments").select("storage_path").eq("org_id",parsed.data.org_id).eq("id",parsed.data.receipt_id).maybeSingle();
 if(error||!receipt)return {error:error?.message??"Receipt not found."};
 const {data:signed,error:signedError}=await supabase.storage.from("linkora-finance-receipts").createSignedUrl(receipt.storage_path,60);
 if(signedError)return {error:signedError.message};return {url:signed.signedUrl};
}
