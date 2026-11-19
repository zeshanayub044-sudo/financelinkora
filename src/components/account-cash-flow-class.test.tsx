import {afterEach,describe,expect,it,vi} from "vitest";
import {cleanup,fireEvent,render,screen,waitFor} from "@testing-library/react";
import {AccountCashFlowClass} from "./account-cash-flow-class";
const actions=vi.hoisted(()=>({updateAccountCashFlowClassAction:vi.fn()}));
vi.mock("@/app/(workspace)/actions",()=>actions);
vi.mock("next/navigation",()=>({useRouter:()=>({refresh:vi.fn()})}));
afterEach(cleanup);
describe("cash-flow account classification",()=>{
 it("offers explicit activity classes for non-cash accounts",()=>{
  render(<AccountCashFlowClass orgId="org" accountId="revenue" value="operating" reportingClass={null} canEdit/>);
  expect(screen.getByRole("option",{name:"Operating"})).toBeInTheDocument();
  expect(screen.getByRole("option",{name:"Investing"})).toBeInTheDocument();
  expect(screen.getByRole("option",{name:"Financing"})).toBeInTheDocument();
  expect(screen.getByRole("option",{name:"Unclassified"})).toBeInTheDocument();
 });
 it("keeps cash and bank accounts in cash equivalents",()=>{
  render(<AccountCashFlowClass orgId="org" accountId="cash" value="unclassified" reportingClass="cash" canEdit/>);
  expect(screen.getByText("Cash and cash equivalents")).toBeInTheDocument();
  expect(screen.queryByRole("combobox")).toBeNull();
 });
 it("reports a thrown classification update and refreshes the authoritative value",async()=>{
  actions.updateAccountCashFlowClassAction.mockRejectedValueOnce(new Error("network unavailable"));
  render(<AccountCashFlowClass orgId="org" accountId="revenue" value="operating" reportingClass={null} canEdit/>);
  fireEvent.change(screen.getByRole("combobox"),{target:{value:"investing"}});
  expect(await screen.findByRole("alert")).toHaveTextContent("request failed");
  await waitFor(()=>expect(screen.getByRole("combobox")).toBeEnabled());
 });
});
