export const LINKORA_SUPABASE_URL="https://jztejhppiepczvqiebik.supabase.co";

/** Accept only the explicitly selected hosted project or the local Supabase API. */
export function isAllowedSupabaseUrl(value:string|undefined):boolean{
 if(!value)return false;
 try{
  const url=new URL(value);
  if(url.username||url.password||url.pathname!=="/"||url.search||url.hash)return false;
  if(url.protocol==="https:"&&url.hostname==="jztejhppiepczvqiebik.supabase.co"&&(url.port===""||url.port==="443"))return true;
  return url.protocol==="http:"&&["localhost","127.0.0.1","[::1]"].includes(url.hostname)&&url.port==="54321";
 }catch{return false;}
}

export function hasSupabasePublicConfig(url:string|undefined,key:string|undefined):boolean{
 return isAllowedSupabaseUrl(url)&&Boolean(key?.trim());
}

export const supabaseConfigured=hasSupabasePublicConfig(
 process.env.NEXT_PUBLIC_SUPABASE_URL,
 process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
);
