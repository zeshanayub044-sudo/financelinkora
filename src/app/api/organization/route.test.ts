import { beforeEach, describe, expect, it, vi } from "vitest";

const { createClientMock, cookiesMock } = vi.hoisted(() => ({ createClientMock: vi.fn(), cookiesMock: vi.fn() }));
vi.mock("@/lib/supabase/server", () => ({ createClient: createClientMock }));
vi.mock("next/headers", () => ({ cookies: cookiesMock }));

import { POST } from "./route";

const user = { id: "user-123" };
const org = "org-123";

function request() {
  const body = new FormData();
  body.set("org_id", org);
  return new Request("http://localhost/api/organization", { method: "POST", body });
}

describe("organization selection route", () => {
  const setCookie = vi.fn();
  const maybeSingle = vi.fn();
  const eqUser = vi.fn(() => ({ maybeSingle }));
  const eqOrg = vi.fn(() => ({ eq: eqUser }));
  const select = vi.fn(() => ({ eq: eqOrg }));
  const from = vi.fn(() => ({ select }));

  beforeEach(() => {
    vi.clearAllMocks();
    cookiesMock.mockResolvedValue({ set: setCookie });
    createClientMock.mockResolvedValue({ auth: { getUser: vi.fn().mockResolvedValue({ data: { user } }) }, from });
  });

  it("stores the selection only after confirming the signed-in user's membership", async () => {
    maybeSingle.mockResolvedValue({ data: { org_id: org }, error: null });
    const response = await POST(request());
    expect(response.status).toBe(200);
    expect(eqOrg).toHaveBeenCalledWith("org_id", org);
    expect(eqUser).toHaveBeenCalledWith("user_id", user.id);
    expect(setCookie).toHaveBeenCalledWith("linkora_org", org, expect.objectContaining({ httpOnly: true, sameSite: "lax" }));
  });

  it("does not set the cookie for a different member's organization", async () => {
    maybeSingle.mockResolvedValue({ data: null, error: null });
    const response = await POST(request());
    expect(response.status).toBe(403);
    expect(setCookie).not.toHaveBeenCalled();
  });

  it("rejects unauthenticated requests before checking membership", async () => {
    createClientMock.mockResolvedValue({ auth: { getUser: vi.fn().mockResolvedValue({ data: { user: null } }) }, from });
    const response = await POST(request());
    expect(response.status).toBe(401);
    expect(from).not.toHaveBeenCalled();
    expect(setCookie).not.toHaveBeenCalled();
  });
});
