import {afterEach,describe,expect,it,vi} from "vitest";
import {cleanup,fireEvent,render,screen} from "@testing-library/react";
import {AccountForm} from "./account-form";

const actions=vi.hoisted(()=>({createAccountAction:vi.fn()}));
vi.mock("@/app/(workspace)/actions",()=>actions);
afterEach(()=>{cleanup();vi.clearAllMocks()});

describe("chart of accounts form",()=>{
  it("shows a retryable failure and retains the account details when creation throws",async()=>{
    actions.createAccountAction.mockRejectedValueOnce(new Error("network unavailable"));
    render(<AccountForm orgId="org"/>);
    fireEvent.click(screen.getByRole("button",{name:"Add account"}));
    fireEvent.change(screen.getByLabelText("Code"),{target:{value:"1010"}});
    fireEvent.change(screen.getByLabelText("Name"),{target:{value:"Operating bank"}});
    fireEvent.submit(screen.getByLabelText("Code").closest("form")!);
    expect(await screen.findByRole("alert")).toHaveTextContent("entries are still in this form");
    expect((screen.getByLabelText("Code") as HTMLInputElement).value).toBe("1010");
    expect((screen.getByLabelText("Name") as HTMLInputElement).value).toBe("Operating bank");
  });
});
