import { createBrowserClient } from "@supabase/ssr";
import type { Database } from "@/lib/database.types";
import {isAllowedSupabaseUrl} from "@/lib/supabase/config";
export function createClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url) throw new Error("Supabase is not configured. Add the project URL to .env.local.");
  if (!isAllowedSupabaseUrl(url)) throw new Error("Supabase URL must point to the selected Linkora Finance project or the local Supabase API.");
  if (!key) throw new Error("Supabase is not configured. Add the publishable key to .env.local.");
  return createBrowserClient<Database>(url, key);
}
