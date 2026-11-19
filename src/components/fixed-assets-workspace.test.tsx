import {afterEach,describe,expect,it,vi} from "vitest";
import {cleanup,fireEvent,render,screen,waitFor} from "@testing-library/react";
import {FixedAssetForm,compareFixedAssetAmounts} from "@/components/fixed-assets-workspace";

const actions=vi.hoisted(()=>({registerFixedAssetAction:vi.fn()}));
const nav=vi.hoisted(()=>({refresh:vi.fn()}));
vi.mock("@/app/(workspace)/actions",()=>actions);
vi.mock("next/navigation",()=>({useRouter:()=>nav}));
afterEach(()=>{cleanup();vi.clearAllMocks()});

describe("fixed asset disposal amount comparison",()=>{
  it("compares four-place decimal values without floating point",()=>{
    expect(compareFixedAssetAmounts("1000000000000000.0001","1000000000000000.0000")).toBe(1);
    expect(compareFixedAssetAmounts("9007199254740993","9007199254740992")).toBe(1);
    expect(compareFixedAssetAmounts("14.2500","14.25")).toBe(0);
    expect(compareFixedAssetAmounts("0.0001","0.0002")).toBe(-1);
  });
});

describe("fixed asset registration form",()=>{
  it("keeps the form usable when registration throws",async()=>{
    actions.registerFixedAssetAction.mockRejectedValueOnce(new Error("network unavailable"));
    render(<FixedAssetForm orgId="org" entries={[{id:"posted-entry",entry_no:"JE-1",entry_date:"2026-11-01",description:"Asset purchase"}]} accounts={[
      {id:"asset",code:"1500",name:"Equipment",type:"asset",reporting_class:null,normal_balance:"debit"},
      {id:"accum",code:"1590",name:"Accumulated depreciation",type:"asset",reporting_class:"accumulated_depreciation",normal_balance:"credit"},
      {id:"expense",code:"5100",name:"Depreciation",type:"expense",reporting_class:null,normal_balance:"debit"},
    ]}/>);
    fireEvent.change(screen.getByLabelText("Asset code"),{target:{value:"LAPTOP-1"}});
    fireEvent.change(screen.getByLabelText("Asset name"),{target:{value:"Office laptop"}});
    fireEvent.change(screen.getByLabelText("Posted acquisition journal"),{target:{value:"posted-entry"}});
    fireEvent.change(screen.getByLabelText("Acquisition date"),{target:{value:"2026-11-01"}});
    fireEvent.change(screen.getByLabelText("In-service date"),{target:{value:"2026-11-02"}});
    fireEvent.change(screen.getByLabelText(/Acquisition cost/),{target:{value:"1200.00"}});
    fireEvent.change(screen.getByLabelText("Fixed asset account"),{target:{value:"asset"}});
    fireEvent.change(screen.getByLabelText("Accumulated depreciation (contra-asset)"),{target:{value:"accum"}});
    fireEvent.change(screen.getByLabelText("Depreciation expense account"),{target:{value:"expense"}});
    fireEvent.submit(screen.getByLabelText("Asset code").closest("form")!);
    expect(await screen.findByRole("alert")).toHaveTextContent("request failed");
    expect((screen.getByLabelText("Asset code") as HTMLInputElement).value).toBe("LAPTOP-1");
    expect((screen.getByLabelText("Asset name") as HTMLInputElement).value).toBe("Office laptop");
    await waitFor(()=>expect(screen.getByRole("button",{name:"Register asset"})).toBeEnabled());
  });
});
