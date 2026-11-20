export const LINKORA_SUPABASE_URL="https://jztejhppiepczvqiebik.supabase.co";

/** Use the approved project by default; local Supabase remains an explicit override. */
export function resolveSupabaseUrl(value:string|undefined):string{
 return value?.trim()||LINKORA_SUPABASE_URL;
}

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
 resolveSupabaseUrl(process.env.NEXT_PUBLIC_SUPABASE_URL),
 process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
);
