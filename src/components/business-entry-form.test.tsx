import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { BusinessEntryForm } from "./business-entry-form";

const action = vi.hoisted(() => ({ createBusinessJournalAction: vi.fn() }));
const nav = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock("@/app/(workspace)/actions", () => action);
vi.mock("next/navigation", () => ({ useRouter: () => nav }));
const accounts = [
  { id: "asset-a", code: "1000", name: "Cash", type: "asset", reporting_class:"cash" },
  { id: "asset-b", code: "1010", name: "Bank", type: "asset", reporting_class:"bank" },
  { id: "revenue-a", code: "4000", name: "Sales", type: "revenue" },
  { id: "expense-a", code: "5000", name: "Supplies", type: "expense" },
];
afterEach(() => { cleanup(); vi.clearAllMocks(); });

describe("business accounting entry forms", () => {
  it("limits income categories to revenue accounts", () => {
    render(<BusinessEntryForm orgId="org-id" kind="income" accounts={accounts} />);
    expect(screen.getByRole("option", { name: "4000 · Sales" })).toBeInTheDocument();
    expect(screen.queryByRole("option", { name: "5000 · Supplies" })).toBeNull();
  });
  it("prevents choosing the source as the transfer destination", () => {
    render(<BusinessEntryForm orgId="org-id" kind="bank_transfer" accounts={accounts} />);
    const destination = screen.getByLabelText("To cash/bank account") as HTMLSelectElement;
    fireEvent.change(screen.getByLabelText("From cash/bank account"), { target: { value: "asset-a" } });
    expect(destination.querySelector('option[value="asset-a"]')).toBeNull();
    expect(destination.querySelector('option[value="asset-b"]')).not.toBeNull();
  });
  it("uses classified cash accounts and an explicit offset for bank deposits",()=>{
    render(<BusinessEntryForm orgId="org-id" kind="bank_deposit" accounts={accounts}/>);
    expect(screen.getByLabelText("Receiving cash/bank account").querySelector('option[value="asset-a"]')).not.toBeNull();
    expect(screen.getByLabelText("Receiving cash/bank account").querySelector('option[value="revenue-a"]')).toBeNull();
    expect(screen.getByLabelText("Offset account").querySelector('option[value="revenue-a"]')).not.toBeNull();
    expect(screen.getByLabelText("Offset account").querySelector('option[value="asset-b"]')).toBeNull();
  });
  it("preserves income draft details and allows retry when the save action throws",async()=>{
    action.createBusinessJournalAction.mockRejectedValueOnce(new Error("network unavailable"));
    render(<BusinessEntryForm orgId="org-id" kind="income" accounts={accounts}/>);
    fireEvent.change(screen.getByLabelText("Revenue category"),{target:{value:"revenue-a"}});
    fireEvent.change(screen.getByLabelText("Receiving cash/bank account"),{target:{value:"asset-a"}});
    fireEvent.change(screen.getByLabelText("Amount"),{target:{value:"42.50"}});
    fireEvent.change(screen.getByLabelText("Description"),{target:{value:"Consulting income"}});
    fireEvent.submit(screen.getByLabelText("Description").closest("form")!);
    expect(await screen.findByRole("alert")).toHaveTextContent("Your entries are still in this form");
    expect((screen.getByLabelText("Amount") as HTMLInputElement).value).toBe("42.50");
    expect((screen.getByLabelText("Description") as HTMLInputElement).value).toBe("Consulting income");
    await waitFor(()=>expect(screen.getByRole("button",{name:"Save accounting draft"})).toBeEnabled());
  });
});
