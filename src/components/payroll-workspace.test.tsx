import {afterEach,describe,expect,it,vi} from "vitest";
import {cleanup,render,screen} from "@testing-library/react";
import {PayrollWorkspace} from "./payroll-workspace";
vi.mock("@/app/(workspace)/actions",()=>({createPayrollComponentAction:vi.fn(),createPayrollEmployeeAction:vi.fn(),createPayrollRunAction:vi.fn(),submitPayrollRunAction:vi.fn(),updatePayrollRunAction:vi.fn()}));
vi.mock("next/navigation",()=>({useRouter:()=>({refresh:vi.fn(),push:vi.fn()})}));
afterEach(cleanup);
const props={orgId:"org",userId:"maker",currency:"USD",employees:[],components:[],accounts:[],runs:[]};
describe("payroll workspace",()=>{
 it("hides compensation records from roles without payroll access",()=>{
  render(<PayrollWorkspace {...props} role="employee"/>);
  expect(screen.getByText("Payroll access is restricted because this module contains confidential employee compensation records.")).toBeInTheDocument();
  expect(screen.queryByText("Create monthly payroll draft")).not.toBeInTheDocument();
 });
 it("shows honest empty states and does not invent run balances",()=>{
  render(<PayrollWorkspace {...props} role="accountant"/>);
  expect(screen.getByText("No employee records yet.")).toBeInTheDocument();
  expect(screen.getByText("No payroll runs. Create a draft once the employee, component, and account setup is complete.")).toBeInTheDocument();
 });
});
