import {describe,expect,it} from "vitest";
import {hasSupabasePublicConfig,isAllowedSupabaseUrl,LINKORA_SUPABASE_URL,resolveSupabaseUrl} from "./config";

describe("Supabase project guard",()=>{
 it("defaults to the approved project and allows an explicit local override",()=>{
  expect(resolveSupabaseUrl(undefined)).toBe(LINKORA_SUPABASE_URL);
  expect(resolveSupabaseUrl(" ")).toBe(LINKORA_SUPABASE_URL);
  expect(resolveSupabaseUrl("http://localhost:54321")).toBe("http://localhost:54321");
 });
 it("accepts only the approved hosted Linkora project",()=>{
  expect(isAllowedSupabaseUrl(LINKORA_SUPABASE_URL)).toBe(true);
  expect(isAllowedSupabaseUrl("https://unrelated-project.supabase.co")).toBe(false);
  expect(isAllowedSupabaseUrl("https://jztejhppiepczvqiebik.supabase.co.attacker.invalid")).toBe(false);
 });
 it("allows the local Supabase API but rejects non-local HTTP endpoints",()=>{
  expect(isAllowedSupabaseUrl("http://127.0.0.1:54321")).toBe(true);
  expect(isAllowedSupabaseUrl("http://localhost:54321")).toBe(true);
  expect(isAllowedSupabaseUrl("http://localhost:8000")).toBe(false);
  expect(isAllowedSupabaseUrl("http://192.168.1.25:54321")).toBe(false);
 });
 it("requires both an allowed URL and a public client key",()=>{
  expect(hasSupabasePublicConfig(LINKORA_SUPABASE_URL,"sb_publishable_test")).toBe(true);
  expect(hasSupabasePublicConfig(LINKORA_SUPABASE_URL," ")).toBe(false);
  expect(hasSupabasePublicConfig("https://other.supabase.co","sb_publishable_test")).toBe(false);
 });
});
