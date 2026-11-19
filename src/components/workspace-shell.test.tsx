import { afterEach, describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";
import { WorkspaceShell } from "./workspace-shell";

const signOutMock = vi.hoisted(() => vi.fn());
vi.mock("next/navigation", () => ({ usePathname: () => "/dashboard", useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }) }));
vi.mock("next/image", () => ({ default: (props: React.ImgHTMLAttributes<HTMLImageElement> & { priority?: boolean }) => {
  const { priority, ...imageProps } = props;
  void priority;
  return <span role="img" aria-label={imageProps.alt} data-src={imageProps.src} />;
} }));
vi.mock("@/lib/supabase/client", () => ({ createClient: () => ({ auth: { signOut: signOutMock } }) }));

const shellProps = {
  org: { id: "org", name: "Northstar", base_currency: "PKR" },
  orgs: [],
  user: { email: "user@example.com" },
};

describe("workspace shell", () => {
  afterEach(()=>{vi.unstubAllGlobals();signOutMock.mockReset().mockResolvedValue({error:null});});
  it("opens the small-screen navigation drawer", () => {
    const { container } = render(<WorkspaceShell {...shellProps}>Workspace</WorkspaceShell>);
    fireEvent.click(screen.getByRole("button", { name: "Open navigation" }));
    expect(container.querySelector(".fixed.inset-0.z-40")).toBeInTheDocument();
    expect(screen.getAllByRole("button", { name: "Close navigation" }).length).toBeGreaterThan(0);
  });

  it("shows database-backed approval items in the workflow inbox", () => {
    render(<WorkspaceShell {...shellProps} workflowItems={[{
      id: "entry-1", entryNo: "JE-0001", description: "Rent for May", status: "pending_approval",
    }]}>Workspace</WorkspaceShell>);
    fireEvent.click(screen.getByRole("button", { name: "Workflow inbox, 1 items" }));
    expect(screen.getByRole("dialog", { name: "Workflow inbox" })).toBeInTheDocument();
    expect(screen.getByText("JE-0001 · Pending review")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /JE-0001/ })).toHaveAttribute("href", "/journal-entries/entry-1");
  });

  it("distinguishes an empty inbox from a failed inbox query", () => {
    const { rerender } = render(<WorkspaceShell {...shellProps}>Workspace</WorkspaceShell>);
    fireEvent.click(screen.getByRole("button", { name: "Workflow inbox" }));
    expect(screen.getByText("No pending approvals or approved entries are waiting in this organization.")).toBeInTheDocument();

    rerender(<WorkspaceShell {...shellProps} workflowUnavailable>Workspace</WorkspaceShell>);
    expect(screen.getByRole("alert")).toHaveTextContent("temporarily unavailable");
  });

  it("restores the selected organization and reports access errors when switching fails", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ok:false,json:async()=>({error:"Organization access denied"})}));
    render(<WorkspaceShell {...shellProps} orgs={[shellProps.org,{id:"other",name:"Other workspace",base_currency:"USD"}]}>Workspace</WorkspaceShell>);
    const selector=screen.getByRole("combobox",{name:"Select organization"}) as HTMLSelectElement;
    fireEvent.change(selector,{target:{value:"other"}});
    expect(await screen.findByRole("alert")).toHaveTextContent("Organization access denied");
    expect(selector.value).toBe("org");
  });

  it("reports a sign-out failure and keeps the workspace mounted", async () => {
    signOutMock.mockResolvedValue({error:new Error("Network failure")});
    render(<WorkspaceShell {...shellProps}>Workspace</WorkspaceShell>);
    fireEvent.click(screen.getByRole("button", {name:"Sign out"}));
    expect(await screen.findByRole("alert")).toHaveTextContent("Sign out failed");
    expect(screen.getByRole("main")).toHaveTextContent("Workspace");
  });
});
