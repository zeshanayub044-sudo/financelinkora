import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { JournalForm } from "./journal-form";

const actions = vi.hoisted(() => ({ createJournalAction: vi.fn(), updateJournalAction: vi.fn() }));
vi.mock("@/app/(workspace)/actions", () => actions);
vi.mock("next/navigation", () => ({ useRouter: () => ({ push: vi.fn() }) }));
const accounts = [
  { id: "00000000-0000-4000-8000-000000000001", code: "1000", name: "Cash", type: "asset" },
  { id: "00000000-0000-4000-8000-000000000002", code: "2000", name: "Payable", type: "liability" },
  { id: "00000000-0000-4000-8000-000000000003", code: "3000", name: "Capital", type: "equity" },
  { id: "00000000-0000-4000-8000-000000000004", code: "4000", name: "Revenue", type: "revenue" },
  { id: "00000000-0000-4000-8000-000000000005", code: "5000", name: "Expense", type: "expense" },
];
afterEach(() => { cleanup(); vi.clearAllMocks(); });

describe("opening balance entry form", () => {
  it("shows opening balances only when permitted and limits its accounts to balance sheet classes", () => {
    const { rerender } = render(<JournalForm orgId="00000000-0000-4000-8000-000000000099" currency="PKR" accounts={accounts} />);
    expect(screen.queryByLabelText("Entry type")).toBeNull();
    rerender(<JournalForm orgId="00000000-0000-4000-8000-000000000099" currency="PKR" accounts={accounts} allowOpeningBalance />);
    fireEvent.change(screen.getByLabelText("Entry type"), { target: { value: "opening_balance" } });
    const accountSelects = screen.getAllByRole("combobox", { name: /Account line/ });
    for (const select of accountSelects) {
      expect(select.querySelector('option[value="00000000-0000-4000-8000-000000000001"]')).not.toBeNull();
      expect(select.querySelector('option[value="00000000-0000-4000-8000-000000000004"]')).toBeNull();
      expect(select.querySelector('option[value="00000000-0000-4000-8000-000000000005"]')).toBeNull();
    }
  });
  it("keeps rejected income drafts editable with the correct account classes", () => {
    render(<JournalForm orgId="00000000-0000-4000-8000-000000000099" currency="PKR" accounts={accounts} entryId="entry-id" initialValues={{entry_kind:"income",lines:[{account_id:accounts[0]!.id,debit:"10",credit:"0",memo:null},{account_id:accounts[3]!.id,debit:"0",credit:"10",memo:null}]}}/>);
    expect(screen.queryByLabelText("Entry type")).toBeNull();
    for (const select of screen.getAllByRole("combobox", { name: /Account line/ })) {
      expect(select.querySelector(`option[value="${accounts[3]!.id}"]`)).not.toBeNull();
      expect(select.querySelector(`option[value="${accounts[4]!.id}"]`)).toBeNull();
    }
  });
  it("allows new manual foreign-currency journals and uppercases the currency code",()=>{
    render(<JournalForm orgId="00000000-0000-4000-8000-000000000099" currency="USD" accounts={accounts}/>);
    const code=screen.getByLabelText("Transaction currency") as HTMLInputElement;
    const rate=screen.getByLabelText("Exchange rate") as HTMLInputElement;
    fireEvent.change(code,{target:{value:"eur"}});
    fireEvent.change(rate,{target:{value:"1.23456789"}});
    expect(code.value).toBe("EUR");
    expect(rate.value).toBe("1.23456789");
  });
  it("offers existing department and project allocations per journal line",()=>{
    render(<JournalForm orgId="00000000-0000-4000-8000-000000000099" currency="USD" accounts={accounts} departments={[{id:"00000000-0000-4000-8000-000000000101",code:"OPS",name:"Operations"}]} projects={[{id:"00000000-0000-4000-8000-000000000102",code:"PRJ-1",name:"Implementation"}]}/>);
    expect(screen.getAllByRole("option",{name:"OPS · Operations"})).toHaveLength(2);
    expect(screen.getAllByRole("option",{name:"PRJ-1 · Implementation"})).toHaveLength(2);
    expect(screen.getByLabelText("Department line 1")).toBeInTheDocument();
    expect(screen.getByLabelText("Project line 1")).toBeInTheDocument();
  });
  it("locks transaction currency and exchange rate when editing an existing draft",()=>{
    render(<JournalForm orgId="00000000-0000-4000-8000-000000000099" currency="USD" accounts={accounts} entryId="entry-id" initialValues={{currency:"EUR",exchange_rate:"1.23456789"}}/>);
    expect(screen.getByLabelText("Transaction currency")).toHaveAttribute("readonly");
    expect(screen.getByLabelText("Exchange rate")).toHaveAttribute("readonly");
    expect((screen.getByLabelText("Exchange rate") as HTMLInputElement).value).toBe("1.23456789");
  });
  it("shows a recoverable error and re-enables the form when saving throws",async()=>{
    actions.createJournalAction.mockRejectedValueOnce(new Error("network unavailable"));
    render(<JournalForm orgId="00000000-0000-4000-8000-000000000099" currency="PKR" accounts={accounts} initialValues={{description:"Opening balance",lines:[
      {account_id:accounts[0]!.id,debit:"10",credit:"0",memo:null},
      {account_id:accounts[2]!.id,debit:"0",credit:"10",memo:null},
    ]}}/>);
    fireEvent.submit(screen.getByRole("button",{name:"Save draft"}).closest("form")!);
    expect(await screen.findByRole("status")).toHaveTextContent("Your changes are still in this form");
    await waitFor(()=>expect(screen.getByRole("button",{name:"Save draft"})).toBeEnabled());
    expect((screen.getByLabelText("Description") as HTMLInputElement).value).toBe("Opening balance");
    expect(actions.createJournalAction).toHaveBeenCalledTimes(1);
  });
});
