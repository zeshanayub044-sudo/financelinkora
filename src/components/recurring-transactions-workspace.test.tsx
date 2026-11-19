import {afterEach,describe,expect,it,vi} from "vitest";
import {cleanup,render,screen} from "@testing-library/react";
import {RecurringTransactionsWorkspace} from "./recurring-transactions-workspace";
vi.mock("@/app/(workspace)/actions",()=>({createRecurringTemplateAction:vi.fn(),generateRecurringDraftAction:vi.fn(),setRecurringTemplateActiveAction:vi.fn()}));
vi.mock("next/navigation",()=>({useRouter:()=>({refresh:vi.fn(),push:vi.fn()})}));
afterEach(cleanup);
const base={orgId:"org",kind:"income" as const,currency:"PKR",accounts:[],templates:[],occurrences:[],canManage:true};
describe("recurring transaction controls",()=>{
 it("shows a real empty state and makes first generation an explicit action",()=>{
  render(<RecurringTransactionsWorkspace {...base}/>);
  expect(screen.getByText("No recurring schedules configured.")).toBeInTheDocument();
  expect(screen.getByText(/They never auto-approve or auto-post/)).toBeInTheDocument();
  expect(screen.getByRole("button",{name:"Create schedule"})).toBeDisabled();
 });
 it("shows the next due date and generated journal status for configured schedules",()=>{
  render(<RecurringTransactionsWorkspace {...base} templates={[{id:"template",name:"Monthly consulting",transaction_kind:"income",frequency:"monthly",start_date:"2026-11-18",end_date:null,next_date:"2026-12-18",amount:"500.0000",category_account_id:"revenue",asset_account_id:"cash",description:"Consulting fee",reference_prefix:"CONS",is_active:true}]} occurrences={[{template_id:"template",scheduled_date:"2026-11-18",journal_entry_id:"journal",entry_no:"JE-000010",status:"posted"}]}/>);
  expect(screen.getByText(/monthly · 2026-12-18/i)).toBeInTheDocument();
  expect(screen.getByText("posted")).toBeInTheDocument();
  expect(screen.getByRole("link",{name:"JE-000010"})).toHaveAttribute("href","/journal-entries/journal");
 });
});
