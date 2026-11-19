import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const { addMember, setRole, removeMember, refresh }=vi.hoisted(()=>({addMember:vi.fn(),setRole:vi.fn(),removeMember:vi.fn(),refresh:vi.fn()}));
vi.mock("next/navigation",()=>({useRouter:()=>({refresh})}));
vi.mock("@/app/(workspace)/actions",()=>({addOrganizationMemberAction:addMember,setOrganizationMemberRoleAction:setRole,removeOrganizationMemberAction:removeMember}));
import { MemberManagement } from "./member-management";

const userId="00000000-0000-4000-8000-000000000001";
const orgId="00000000-0000-4000-8000-000000000002";

describe("organization member management",()=>{
  beforeEach(()=>{vi.clearAllMocks();vi.stubGlobal("confirm",vi.fn(()=>true));addMember.mockResolvedValue({ok:true});setRole.mockResolvedValue({ok:true});removeMember.mockResolvedValue({ok:true});});

  it("lets an owner add an existing Auth user with a role",async()=>{
    render(<MemberManagement orgId={orgId} currentRole="owner" currentUserId={userId} members={[]}/>);
    fireEvent.change(screen.getByLabelText("Supabase user UUID"),{target:{value:userId}});
    fireEvent.change(screen.getByLabelText("Organization role"),{target:{value:"approver"}});
    fireEvent.click(screen.getByRole("button",{name:"Add member"}));
    await waitFor(()=>expect(addMember).toHaveBeenCalledWith({org_id:orgId,user_id:userId,role:"approver"}));
  });

  it("does not offer owner or administrator roles to administrators",()=>{
    render(<MemberManagement orgId={orgId} currentRole="administrator" currentUserId={userId} members={[]}/>);
    const roleSelect=screen.getByLabelText("Organization role");
    expect(Array.from((roleSelect as HTMLSelectElement).options).map(option=>option.value)).not.toContain("owner");
    expect(Array.from((roleSelect as HTMLSelectElement).options).map(option=>option.value)).not.toContain("administrator");
  });

  it("does not expose controls to administrators for owner accounts",()=>{
    render(<MemberManagement orgId={orgId} currentRole="administrator" currentUserId={userId} members={[{user_id:userId,role:"owner"}]}/>);
    expect(screen.queryByLabelText("Role for "+userId)).toBeNull();
    expect(screen.queryByRole("button",{name:"Remove"})).toBeNull();
    expect(screen.getByText("Owner")).toBeTruthy();
  });

  it("routes allowed role changes through the server action",async()=>{
    render(<MemberManagement orgId={orgId} currentRole="owner" currentUserId={userId} members={[{user_id:orgId,role:"viewer"}]}/>);
    fireEvent.change(screen.getByLabelText("Role for "+orgId),{target:{value:"accountant"}});
    fireEvent.click(screen.getByRole("button",{name:"Save role"}));
    await waitFor(()=>expect(setRole).toHaveBeenCalledWith({org_id:orgId,user_id:orgId,role:"accountant"}));
  });

  it("surfaces uncertain membership failures and keeps the user UUID available",async()=>{
    addMember.mockRejectedValueOnce(new Error("network unavailable"));
    render(<MemberManagement orgId={orgId} currentRole="owner" currentUserId={userId} members={[]}/>);
    const input=screen.getByLabelText("Supabase user UUID") as HTMLInputElement;
    fireEvent.change(input,{target:{value:userId}});
    fireEvent.click(screen.getByRole("button",{name:"Add member"}));
    expect(await screen.findByRole("alert")).toHaveTextContent("status may be uncertain");
    expect(input.value).toBe(userId);
  });
});
