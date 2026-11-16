import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) return response;
  const supabase = createServerClient(url, key, { cookies: { getAll: () => request.cookies.getAll(), setAll(values,headers) { values.forEach(({name,value}) => request.cookies.set(name,value)); response = NextResponse.next({ request }); values.forEach(({name,value,options}) => response.cookies.set(name,value,options)); Object.entries(headers).forEach(([name,value])=>response.headers.set(name,value)); } } });
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;
  const path = request.nextUrl.pathname;
  const publicPath = ["/login","/forgot-password","/reset-password","/auth/callback","/unauthorized"].some((p) => path === p || path.startsWith(`${p}/`));
  if (!claims && !publicPath) { const target = request.nextUrl.clone(); target.pathname = "/login"; target.searchParams.set("next", path); return NextResponse.redirect(target); }
  if (claims && path === "/login") { const target = request.nextUrl.clone(); target.pathname = "/dashboard"; target.search = ""; return NextResponse.redirect(target); }
  response.headers.set("Cache-Control", "private, no-cache, no-store, must-revalidate, max-age=0");
  return response;
}
