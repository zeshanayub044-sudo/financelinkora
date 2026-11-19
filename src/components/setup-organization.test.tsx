import {afterEach,describe,expect,it,vi} from "vitest";
import {cleanup,fireEvent,render,screen} from "@testing-library/react";
import {SetupOrganization} from "./setup-organization";

const api=vi.hoisted(()=>({rpc:vi.fn()}));
vi.mock("@/lib/supabase/client",()=>({createClient:()=>({rpc:api.rpc})}));
afterEach(()=>{cleanup();vi.clearAllMocks();vi.unstubAllGlobals()});

describe("organization setup recovery",()=>{
  it("retries selecting an already-created organization without creating a duplicate",async()=>{
    api.rpc.mockResolvedValueOnce({data:"org-id",error:null});
    vi.stubGlobal("fetch",vi.fn().mockResolvedValue({ok:false,json:async()=>({error:"Organization access denied"})}));
    render(<SetupOrganization userName="Owner"/>);
    fireEvent.change(screen.getByLabelText("Organization name"),{target:{value:"Linkora Test"}});
    fireEvent.change(screen.getByLabelText("Your name"),{target:{value:"Owner"}});
    fireEvent.submit(screen.getByLabelText("Organization name").closest("form")!);
    expect(await screen.findByRole("alert")).toHaveTextContent("Organization access denied");
    expect(screen.getByRole("button",{name:"Retry workspace selection"})).toBeEnabled();
    fireEvent.click(screen.getByRole("button",{name:"Retry workspace selection"}));
    expect(await screen.findByRole("alert")).toHaveTextContent("Organization access denied");
    expect(api.rpc).toHaveBeenCalledTimes(1);
    expect(fetch).toHaveBeenCalledTimes(2);
  });
});
