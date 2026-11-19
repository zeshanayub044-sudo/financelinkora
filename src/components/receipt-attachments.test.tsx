import {afterEach,describe,expect,it,vi} from "vitest";
import {cleanup,fireEvent,render,screen} from "@testing-library/react";
import {ReceiptAttachments} from "./receipt-attachments";
const actions=vi.hoisted(()=>({createReceiptSignedUrlAction:vi.fn()}));
vi.mock("@/lib/supabase/client",()=>({createClient:vi.fn()}));
vi.mock("@/app/(workspace)/receipt-actions",()=>actions);
vi.mock("next/navigation",()=>({useRouter:()=>({refresh:vi.fn()})}));
afterEach(()=>{cleanup();vi.clearAllMocks()});
describe("receipt attachment panel",()=>{
 it("lists private receipts without giving read-only users an upload control",()=>{
  render(<ReceiptAttachments orgId="org" entryId="entry" canUpload={false} items={[{id:"receipt",storage_path:"org/entry/file.pdf",original_name:"invoice.pdf",mime_type:"application/pdf",size_bytes:4096,created_at:"2026-11-18T00:00:00Z"}]}/>);
  expect(screen.getByText("invoice.pdf")).toBeInTheDocument();
  expect(screen.getByRole("button",{name:"Open (1 minute)"})).toBeInTheDocument();
  expect(screen.queryByLabelText("Choose receipt")).toBeNull();
 });
 it("shows an explicit empty state when no receipt exists",()=>{
  render(<ReceiptAttachments orgId="org" entryId="entry" canUpload items={[]}/>);
  expect(screen.getByText("No receipt files attached.")).toBeInTheDocument();
  expect(screen.getByLabelText("Choose receipt")).toHaveAttribute("accept","application/pdf,image/jpeg,image/png");
 });
 it("shows a recoverable error when signed-link creation throws",async()=>{
  actions.createReceiptSignedUrlAction.mockRejectedValueOnce(new Error("network unavailable"));
  render(<ReceiptAttachments orgId="org" entryId="entry" canUpload={false} items={[{id:"receipt",storage_path:"org/entry/file.pdf",original_name:"invoice.pdf",mime_type:"application/pdf",size_bytes:4096,created_at:"2026-11-18T00:00:00Z"}]}/>);
  fireEvent.click(screen.getByRole("button",{name:"Open (1 minute)"}));
  expect(await screen.findByRole("alert")).toHaveTextContent("request failed");
 });
});
