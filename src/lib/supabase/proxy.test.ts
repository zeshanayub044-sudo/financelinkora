import {afterEach,describe,expect,it,vi} from "vitest";
import {NextRequest} from "next/server";

const mocks=vi.hoisted(()=>({createServerClient:vi.fn()}));
vi.mock("@supabase/ssr",()=>({createServerClient:mocks.createServerClient}));
import {updateSession} from "./proxy";

const oldUrl=process.env.NEXT_PUBLIC_SUPABASE_URL;
const oldKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
afterEach(()=>{
 vi.clearAllMocks();
 if(oldUrl===undefined)delete process.env.NEXT_PUBLIC_SUPABASE_URL;else process.env.NEXT_PUBLIC_SUPABASE_URL=oldUrl;
 if(oldKey===undefined)delete process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;else process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=oldKey;
});

describe("Supabase request proxy project guard",()=>{
 it("does not call Supabase Auth for an unrelated hosted project",async()=>{
  process.env.NEXT_PUBLIC_SUPABASE_URL="https://unrelated.supabase.co";
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY="sb_publishable_test";
  const response=await updateSession(new NextRequest("http://localhost:3000/dashboard?period=2026-01"));
  expect(mocks.createServerClient).not.toHaveBeenCalled();
  expect(response.status).toBe(200);
 });
 it("checks claims against the exact approved Linkora project",async()=>{
  process.env.NEXT_PUBLIC_SUPABASE_URL="https://jztejhppiepczvqiebik.supabase.co";
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY="sb_publishable_test";
  mocks.createServerClient.mockReturnValue({auth:{getClaims:async()=>({data:{claims:null}})}});
  const response=await updateSession(new NextRequest("http://localhost:3000/dashboard?period=2026-01"));
  expect(mocks.createServerClient).toHaveBeenCalledOnce();
  expect(mocks.createServerClient.mock.calls[0]?.[0]).toBe("https://jztejhppiepczvqiebik.supabase.co");
  expect(response.status).toBe(307);
  expect(response.headers.get("location")).toContain("/login");
  expect(new URL(response.headers.get("location")!).searchParams.get("next")).toBe("/dashboard?period=2026-01");
 });
 it("allows signed-out visitors to reach registration",async()=>{
  process.env.NEXT_PUBLIC_SUPABASE_URL="https://jztejhppiepczvqiebik.supabase.co";
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY="sb_publishable_test";
  mocks.createServerClient.mockReturnValue({auth:{getClaims:async()=>({data:{claims:null}})}});
  const response=await updateSession(new NextRequest("http://localhost:3000/signup"));
  expect(response.status).toBe(200);
  expect(response.headers.get("location")).toBeNull();
 });
});
