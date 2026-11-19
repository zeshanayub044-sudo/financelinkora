import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

const mockExchange = vi.hoisted(() => vi.fn());
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({ auth: { exchangeCodeForSession: mockExchange } }),
}));

import { GET } from "./route";

beforeEach(() => mockExchange.mockReset().mockResolvedValue({ error: null }));
afterEach(() => mockExchange.mockReset());

describe("authentication callback redirect", () => {
  it("redirects to the requested same-origin destination after exchanging the code", async () => {
    const request = new NextRequest("https://finance.example/auth/callback?code=valid&next=%2Freset-password");
    const response = await GET(request);
    expect(mockExchange).toHaveBeenCalledWith("valid");
    expect(response.headers.get("location")).toBe("https://finance.example/reset-password");
  });

  it("rejects URL-normalized external redirect targets", async () => {
    const request = new NextRequest("https://finance.example/auth/callback?code=valid&next=%2F%5Cattacker.example%2Fpath");
    const response = await GET(request);
    expect(response.headers.get("location")).toBe("https://finance.example/dashboard");
  });
});
