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

  it("requires a reason when an authorized checker rejects an entry",async()=>{
    actions.rejectAction.mockResolvedValue({ok:true});
    render(<EntryActions id="entry" status="pending_approval" role="approver" createdBy="maker" currentUserId="checker"/>);
    fireEvent.click(screen.getByRole("button",{name:"Reject"}));
    fireEvent.change(screen.getByLabelText("Rejection reason"),{target:{value:"Incorrect account"}});
    fireEvent.click(screen.getByRole("button",{name:"Confirm rejection"}));
    await waitFor(()=>expect(actions.rejectAction).toHaveBeenCalledWith("entry","Incorrect account"));
  });
});

