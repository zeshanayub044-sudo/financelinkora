import { readFile } from "node:fs/promises";
import path from "node:path";
import { describe, expect, it } from "vitest";

describe("database CI target safety", () => {
  it("runs migration and pgTAP checks only against an isolated local stack", async () => {
    const workflow = await readFile(path.join(process.cwd(), ".github", "workflows", "ci.yml"), "utf8");

    expect(workflow).toContain("supabase start");
    expect(workflow).toContain("supabase db reset --no-seed");
    expect(workflow).toContain("supabase test db");
    expect(workflow).not.toMatch(/--remote|--linked|--db-url|SUPABASE_ACCESS_TOKEN|SUPABASE_DB_PASSWORD/i);
  });

  it("does not configure a service-role credential in browser Supabase code", async () => {
    const root = process.cwd();
    const [client, config, nextConfig, envExample] = await Promise.all([
      readFile(path.join(root, "src", "lib", "supabase", "client.ts"), "utf8"),
      readFile(path.join(root, "src", "lib", "supabase", "config.ts"), "utf8"),
      readFile(path.join(root, "next.config.ts"), "utf8"),
      readFile(path.join(root, ".env.example"), "utf8"),
    ]);

    expect(`${client}\n${config}\n${nextConfig}\n${envExample}`).not.toMatch(/SUPABASE_SERVICE_ROLE_KEY|service_role/i);
  });
});
