import { describe, expect, it } from "vitest";
import { createClient } from "@supabase/supabase-js";

// Deliberately pin this read-only smoke test to the approved Linkora project.
// It cannot accidentally authenticate against another Supabase organization.
const targetUrl = "https://jztejhppiepczvqiebik.supabase.co";
const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const email = process.env.SUPABASE_TEST_EMAIL;
const password = process.env.SUPABASE_TEST_PASSWORD;
const organizationId = process.env.SUPABASE_TEST_ORG_ID;
const enabled = url === targetUrl && Boolean(publishableKey && email && password && organizationId);

describe.skipIf(!enabled)("live Supabase smoke tests (read-only Linkora project)", () => {
  it("authenticates, verifies membership, and reads exact decimal reports", async () => {
    const client = createClient(url!, publishableKey!, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: auth, error: authError } = await client.auth.signInWithPassword({ email: email!, password: password! });
    expect(authError).toBeNull();
    expect(auth.user?.id).toBeTruthy();

    const { data: memberships, error: membershipError } = await client.from("organization_members").select("org_id");
    expect(membershipError).toBeNull();
    expect(memberships?.some(row => row.org_id === organizationId)).toBe(true);

    const { data: trialBalance, error: reportError } = await client.rpc("trial_balance_as_of_exact", {
      p_org: organizationId!, p_as_of: new Date().toISOString().slice(0, 10),
    });
    expect(reportError).toBeNull();
    for (const row of trialBalance ?? []) {
      expect(typeof row.debit).toBe("string");
      expect(typeof row.credit).toBe("string");
    }

    const { data: absentEntryLines, error: lineError } = await client.rpc("journal_entry_lines_exact", {
      p_entry: "00000000-0000-4000-8000-000000000000",
    });
    expect(lineError).toBeNull();
    expect(absentEntryLines).toEqual([]);
    await client.auth.signOut();
  });
});
