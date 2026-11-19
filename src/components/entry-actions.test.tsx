import {afterEach,describe,expect,it,vi} from "vitest";
import {cleanup,fireEvent,render,screen,waitFor} from "@testing-library/react";
import {EntryActions} from "./entry-actions";

const actions=vi.hoisted(()=>({approveAction:vi.fn(),postAction:vi.fn(),queueAction:vi.fn(),rejectAction:vi.fn(),reverseAction:vi.fn(),submitAction:vi.fn()}));
vi.mock("@/app/(workspace)/actions",()=>actions);
vi.mock("next/navigation",()=>({useRouter:()=>({refresh:vi.fn(),push:vi.fn()})}));

afterEach(()=>{cleanup();vi.clearAllMocks();vi.unstubAllGlobals();});

describe("journal workflow controls",()=>{
  it("does not offer a maker approval action",()=>{
    render(<EntryActions id="entry" status="pending_approval" role="approver" createdBy="user-1" currentUserId="user-1"/>);
    expect(screen.queryByRole("button",{name:"Approve"})).toBeNull();
  });

  it("keeps an unbalanced draft editable but blocks submission",()=>{
    render(<EntryActions id="entry" status="draft" role="accountant" createdBy="maker" currentUserId="maker" balanced={false}/>);
    expect(screen.getByRole("link",{name:"Edit draft"})).toHaveAttribute("href","/journal-entries/entry/edit");
    expect(screen.getByRole("button",{name:"Submit for review"})).toBeDisabled();
  });

  it("enables submission for a balanced maker draft",()=>{
    render(<EntryActions id="entry" status="draft" role="accountant" createdBy="maker" currentUserId="maker" balanced/>);
    expect(screen.getByRole("button",{name:"Submit for review"})).toBeEnabled();
  });

  it("requires a reason when an authorized checker rejects an entry",async()=>{
    actions.rejectAction.mockResolvedValue({ok:true});
    render(<EntryActions id="entry" status="pending_approval" role="approver" createdBy="maker" currentUserId="checker"/>);
    fireEvent.click(screen.getByRole("button",{name:"Reject"}));
    fireEvent.change(screen.getByLabelText("Rejection reason"),{target:{value:"Incorrect account"}});
    fireEvent.click(screen.getByRole("button",{name:"Confirm rejection"}));
    await waitFor(()=>expect(actions.rejectAction).toHaveBeenCalledWith("entry","Incorrect account"));
  });

  it("reports a thrown posting action and releases the busy state",async()=>{
    vi.stubGlobal("confirm",()=>true);
    actions.postAction.mockRejectedValueOnce(new Error("network failure"));
    render(<EntryActions id="entry" status="approved" role="accountant" createdBy="maker" currentUserId="checker"/>);
    fireEvent.click(screen.getByRole("button",{name:"Post entry"}));
    expect(await screen.findByRole("alert")).toHaveTextContent("could not be completed");
    expect(screen.getByRole("button",{name:"Post entry"})).toBeEnabled();
  });

  it("recovers from a thrown reversal action",async()=>{
    actions.reverseAction.mockRejectedValueOnce(new Error("network failure"));
    render(<EntryActions id="entry" status="posted" role="accountant" createdBy="maker" currentUserId="checker"/>);
    fireEvent.click(screen.getByRole("button",{name:"Create reversal"}));
    fireEvent.change(screen.getByLabelText("Reversal reason"),{target:{value:"Correct source entry"}});
    fireEvent.click(screen.getByRole("button",{name:"Create reversal draft"}));
    expect(await screen.findByRole("alert")).toHaveTextContent("could not be completed");
    expect(screen.getByRole("button",{name:"Create reversal"})).toBeEnabled();
  });
});
