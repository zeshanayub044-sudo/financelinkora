import {afterEach,describe,expect,it,vi} from "vitest";
import {cleanup,fireEvent,render,screen} from "@testing-library/react";
import {AccountReportingClass} from "./account-reporting-class";

const actions=vi.hoisted(()=>({updateAccountReportingClassAction:vi.fn()}));
vi.mock("@/app/(workspace)/actions",()=>actions);
vi.mock("next/navigation",()=>({useRouter:()=>({refresh:vi.fn()})}));
afterEach(()=>{cleanup();vi.clearAllMocks()});

describe("account reporting classification",()=>{
  it("shows an error and refreshes the authoritative value when the update throws",async()=>{
    actions.updateAccountReportingClassAction.mockRejectedValueOnce(new Error("network unavailable"));
    render(<AccountReportingClass orgId="org" accountId="cash" type="asset" value="cash" canEdit/>);
    fireEvent.change(screen.getByRole("combobox"),{target:{value:"bank"}});
    expect(await screen.findByRole("alert")).toHaveTextContent("request failed");
  });
});
