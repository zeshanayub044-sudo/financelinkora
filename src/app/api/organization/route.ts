import { NextResponse } from "next/server";import { cookies } from "next/headers";import { createClient } from "@/lib/supabase/server";
export async function POST(request:Request){
  let form:FormData;
  try{form=await request.formData();}catch{return NextResponse.json({error:"Invalid organization selection"},{status:400});}
  const orgId=String(form.get("org_id")??"");
  const supabase=await createClient();
  if(!supabase)return NextResponse.json({error:"Supabase is not configured"},{status:503});
  const {data:{user}}=await supabase.auth.getUser();
  if(!user)return NextResponse.json({error:"Sign in to select an organization"},{status:401});
  const {data,error}=await supabase.from("organization_members").select("org_id").eq("org_id",orgId).eq("user_id",user.id).maybeSingle();
  if(error||!data)return NextResponse.json({error:"Organization access denied"},{status:403});
  const jar=await cookies();
  jar.set("linkora_org",orgId,{httpOnly:true,secure:process.env.NODE_ENV==="production",sameSite:"lax",path:"/",maxAge:60*60*24*365});
  return NextResponse.json({ok:true});
}
