import {afterEach,describe,expect,it,vi} from "vitest";

const mocks=vi.hoisted(()=>({from:vi.fn(),rpc:vi.fn(),auth:{getUser:vi.fn()}}));
vi.mock("@/lib/supabase/server",()=>({createClient:async()=>mocks}));
vi.mock("next/headers",()=>({cookies:async()=>({get:()=>undefined})}));
import {getDashboardData,getWorkspace} from "./data";

function queryResult(data:unknown[]=[],error:null|{message:string}=null){
 const result={data,error};const builder:Record<string,unknown>={};
 for(const method of ["select","eq","gte","lte","order","range","limit","in"]){builder[method]=vi.fn(()=>builder);}
 builder.then=(resolve:(value:typeof result)=>unknown)=>Promise.resolve(result).then(resolve);
 return builder;
}

afterEach(()=>vi.clearAllMocks());
describe("dashboard data ranges",()=>{
 it("requests all-history summary KPIs separately from the twelve-month charts",async()=>{
  mocks.from.mockImplementation(()=>queryResult([]));
  mocks.rpc.mockImplementation((name:string)=>name==="financial_summary_exact"?Promise.resolve({data:[{income:"25",expenses:"7",profit:"18",assets:"40",liabilities:"10",equity:"30",cash_balance:"5",bank_balance:"8",accounts_receivable:"2",accounts_payable:"1"}],error:null}):Promise.resolve({data:[],error:null}));
  const result=await getDashboardData("org-id");
  const summaryCall=mocks.rpc.mock.calls.find(([name])=>name==="financial_summary_exact");
  const monthlyCall=mocks.rpc.mock.calls.find(([name])=>name==="monthly_financial_activity_exact");
  expect(summaryCall?.[1]).toMatchObject({p_org:"org-id",p_from:"0001-01-01"});
  expect(monthlyCall?.[1]).not.toHaveProperty("p_from","0001-01-01");
  expect(result?.metrics).toMatchObject({revenue:"25",expenses:"7",profit:"18"});
 });

 it("distinguishes a membership query failure from an account with no organizations",async()=>{
  mocks.auth.getUser.mockResolvedValue({data:{user:{id:"user-id"}},error:null});
  mocks.from.mockReturnValue(queryResult([],{message:"Membership query failed"}));
  const result=await getWorkspace();
  expect(result.org).toBeNull();
  expect(result.error).toBe("Membership query failed");
 });

 it("returns organization selector choices from the same authorized membership result",async()=>{
  mocks.auth.getUser.mockResolvedValue({data:{user:{id:"user-id"}},error:null});
  mocks.from.mockReturnValue(queryResult([{org_id:"org-id",role:"owner",organizations:{id:"org-id",name:"Linkora",base_currency:"PKR",fy_start_month:7}}]));
  const result=await getWorkspace();
  expect(result.org).toMatchObject({id:"org-id",role:"owner"});
  expect(result.orgs).toEqual([{id:"org-id",name:"Linkora",base_currency:"PKR",fy_start_month:7,role:"owner"}]);
 });
});
