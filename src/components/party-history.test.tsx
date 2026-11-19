import {afterEach,describe,expect,it} from "vitest";
import {cleanup,render,screen,within} from "@testing-library/react";
import {PartyHistory,PartyPaymentHistory,type PartyDocument,type PartyPayment} from "./party-history";

afterEach(cleanup);
const documents:PartyDocument[]=[
 {id:"invoice-posted",document_type:"invoice",document_number:"INV-001",issue_date:"2026-01-01",due_date:"2026-01-31",journal_status:"issued",journal_entry_id:"journal-1",total:"15.00",paid:"12.00",outstanding:"3.00",collection_status:"partially_paid"},
 {id:"invoice-draft",document_type:"invoice",document_number:"INV-002",issue_date:"2026-02-01",due_date:"2026-02-28",journal_status:"draft",journal_entry_id:null,total:"50.00",paid:"0.00",outstanding:"50.00",collection_status:"draft"},
];
const payments:PartyPayment[]=[{id:"payment-1",payment_date:"2026-01-12",document_number:"INV-001",amount:"12.00",reference:"BANK-1",account_label:"1100 · Bank",journal_entry_id:"journal-1",journal_status:"posted"},{id:"payment-2",payment_date:"2026-02-12",document_number:"INV-002",amount:"5.00",reference:null,account_label:"1000 · Cash",journal_entry_id:"journal-2",journal_status:"pending_approval"}];
describe("party transaction history",()=>{
 it("summarizes only issued documents while keeping drafts visible in the ledger",()=>{
  render(<PartyHistory documents={documents} currency="USD" documentLabel="Invoices"/>);
  const collected=screen.getByText("Collected / paid on issued invoices").closest("section");
  const outstanding=screen.getByText("Outstanding on issued invoices").closest("section");
  expect(collected&&within(collected).getByText(/12\.00/)).toBeTruthy();
  expect(outstanding&&within(outstanding).getByText(/3\.00/)).toBeTruthy();
  expect(screen.getByText("INV-002")).toBeInTheDocument();
  expect(screen.getByText("draft",{selector:"span"})).toBeInTheDocument();
 });
 it("links issued documents to their actual posted journals",()=>{
  render(<PartyHistory documents={documents} currency="USD" documentLabel="Invoices"/>);
  expect(screen.getByRole("link",{name:"View entry"})).toHaveAttribute("href","/journal-entries/journal-1");
  expect(screen.getByText("Not posted")).toBeInTheDocument();
 });
 it("distinguishes a posted payment from one still awaiting journal approval",()=>{
  render(<PartyPaymentHistory payments={payments} currency="USD"/>);
  expect(screen.getByText("posted",{selector:"span"})).toBeInTheDocument();
  expect(screen.getByText("pending approval",{selector:"span"})).toBeInTheDocument();
  expect(screen.getAllByRole("link",{name:"View entry"})).toHaveLength(2);
 });
});
