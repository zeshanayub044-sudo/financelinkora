import {afterEach,describe,expect,it,vi} from "vitest";
import {cleanup,fireEvent,render,screen} from "@testing-library/react";
import {DocumentForm,DocumentTable,PaymentHistoryTable} from "./receivables-payables-workspace";
const actions=vi.hoisted(()=>({createFinancialDocumentAction:vi.fn(),updateFinancialDocumentDraftAction:vi.fn(),submitFinancialDocumentAction:vi.fn(),recordFinancialDocumentPaymentAction:vi.fn(),createFinancialPartyAction:vi.fn(),correctFinancialDocumentPaymentAction:vi.fn()}));
vi.mock("@/app/(workspace)/actions",()=>actions);
vi.mock("next/navigation",()=>({useRouter:()=>({refresh:vi.fn()})}));
afterEach(()=>{cleanup();vi.clearAllMocks()});
const accounts=[
 {id:"ar",code:"1200",name:"Accounts receivable",type:"asset",reporting_class:"receivable"},
 {id:"ap",code:"2100",name:"Accounts payable",type:"liability",reporting_class:"payable"},
 {id:"income",code:"4000",name:"Services",type:"revenue",reporting_class:null},
 {id:"expense",code:"5000",name:"Supplies",type:"expense",reporting_class:null},
 {id:"cash",code:"1000",name:"Cash",type:"asset",reporting_class:"cash"},
];
describe("receivables and payables UI",()=>{
 it("offers revenue lines and receivables control accounts for invoices",()=>{
  render(<DocumentForm orgId="org" type="invoice" parties={[{id:"customer",name:"Acme",party_type:"customer"}]} accounts={accounts}/>);
  expect(screen.getByRole("option",{name:"1200 · Accounts receivable"})).toBeInTheDocument();
  expect(screen.getByRole("option",{name:"4000 · Services"})).toBeInTheDocument();
  expect(screen.queryByRole("option",{name:"5000 · Supplies"})).toBeNull();
 });
 it("offers expense lines and payables control accounts for bills",()=>{
  render(<DocumentForm orgId="org" type="bill" parties={[{id:"supplier",name:"Vendor",party_type:"supplier"}]} accounts={accounts}/>);
  expect(screen.getByRole("option",{name:"2100 · Accounts payable"})).toBeInTheDocument();
  expect(screen.getByRole("option",{name:"5000 · Supplies"})).toBeInTheDocument();
  expect(screen.queryByRole("option",{name:"4000 · Services"})).toBeNull();
 });
 it("previews configured tax using exact percentage arithmetic",()=>{
  render(<DocumentForm orgId="org" type="invoice" parties={[{id:"customer",name:"Acme",party_type:"customer"}]} accounts={accounts} currency="USD" taxCodes={[{id:"vat",code:"VAT",name:"VAT",scope:"sales",rate:"17.5",effective_from:"2020-01-01",effective_to:null}]}/>);
  fireEvent.change(screen.getByLabelText("Line 1 amount"),{target:{value:"100"}});
  fireEvent.change(screen.getByLabelText("Line 1 tax code"),{target:{value:"vat"}});
  expect(screen.getByText("Tax",{selector:"span"})).toBeInTheDocument();
  expect(screen.getAllByText(/17\.50/).length).toBeGreaterThan(0);
  expect(screen.getAllByText(/117\.50/).length).toBeGreaterThan(0);
 });
 it("does not offer payment entry when the document has no outstanding balance",()=>{
  render(<DocumentTable documents={[{id:"doc",document_type:"invoice",document_number:"I-1",party_name:"Customer",party_id:"customer",control_account_id:"ar",issue_date:"2026-11-18",due_date:"2026-11-18",journal_status:"issued",total:"10.0000",paid:"10.0000",outstanding:"0.0000",collection_status:"paid",created_by:"maker"}]} accounts={accounts} currency="USD" currentUserId="maker"/>);
  expect(screen.queryByRole("button",{name:"Record"})).toBeNull();
  expect(screen.getByRole("link",{name:"View"})).toHaveAttribute("href","/invoices/doc");
 });
 it("shows correction controls only for a creator's rejected payment draft",()=>{
  render(<PaymentHistoryTable currency="USD" currentUserId="maker" accounts={accounts} payments={[{id:"payment",payment_date:"2026-11-18",document_number:"INV-1",document_type:"invoice",amount:"10.0000",account_id:"cash",reference:"R-1",journal_entry_id:"entry",journal_status:"draft",rejection_reason:"Wrong date",created_by:"maker"}]}/>);
  expect(screen.getByText("Reason: Wrong date")).toBeInTheDocument();
  expect(screen.getByText("Correct and resubmit")).toBeInTheDocument();
  expect(screen.getByRole("link",{name:"Open journal"})).toHaveAttribute("href","/journal-entries/entry");
 });
 it("does not permit a different member to correct another maker's payment",()=>{
  render(<PaymentHistoryTable currency="USD" currentUserId="other" accounts={accounts} payments={[{id:"payment",payment_date:"2026-11-18",document_number:"INV-1",document_type:"invoice",amount:"10.0000",account_id:"cash",reference:null,journal_entry_id:"entry",journal_status:"draft",rejection_reason:"Wrong date",created_by:"maker"}]}/>);
  expect(screen.queryByText("Correct and resubmit")).toBeNull();
 });
});
