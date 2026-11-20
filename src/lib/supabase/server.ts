import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import type { Database } from "@/lib/database.types";
import {isAllowedSupabaseUrl,resolveSupabaseUrl} from "@/lib/supabase/config";
export async function createClient() {
  const cookieStore = await cookies();
  const url = resolveSupabaseUrl(process.env.NEXT_PUBLIC_SUPABASE_URL);
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key || !isAllowedSupabaseUrl(url)) return null;
  return createServerClient<Database>(url, key, { cookies: { getAll: () => cookieStore.getAll(), setAll: (values) => { try { values.forEach(({name,value,options}) => cookieStore.set(name,value,options)); } catch {} } } });
}
