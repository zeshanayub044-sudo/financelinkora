import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { describe, expect, it } from "vitest";

async function migrationFiles(directory: string): Promise<string[]> {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(entries.map(async (entry) => {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) return migrationFiles(file);
    return entry.isFile() && entry.name.endsWith(".sql") ? [file] : [];
  }));
  return nested.flat().sort();
}

describe("migration security contract", () => {
  it("enables RLS and declares a policy for every application table", async () => {
    const files = await migrationFiles(path.join(process.cwd(), "supabase", "migrations"));
    const sql = (await Promise.all(files.map((file) => readFile(file, "utf8")))).join("\n");
    const databaseTypes = await readFile(path.join(process.cwd(), "src", "lib", "database.types.ts"), "utf8");
    const tables = new Set([...sql.matchAll(
      /create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?([a-z_][\w]*)/gi,
    )].map((match) => match[1].toLowerCase()));

    const missingRls = [...tables].filter((table) => !new RegExp(
      `alter\\s+table\\s+(?:if\\s+exists\\s+)?(?:public\\.)?${table}\\s+enable\\s+row\\s+level\\s+security`,
      "i",
    ).test(sql));
    const missingPolicy = [...tables].filter((table) => !new RegExp(
      `create\\s+policy\\s+[\\w]+\\s+on\\s+(?:public\\.)?${table}\\b`,
      "i",
    ).test(sql));
    const missingDatabaseTypes = [...tables].filter((table) => !new RegExp(
      `\\b${table}\\s*:\\s*Table\\s*<`,
      "i",
    ).test(databaseTypes));

    const activePolicies = new Map<string, Map<string, string>>();
    const statements = /create\s+policy\s+(\w+)\s+on\s+(?:public\.)?(\w+)[\s\S]*?;|drop\s+policy\s+(?:if\s+exists\s+)?(\w+)\s+on\s+(?:public\.)?(\w+)[^;]*;/gi;
    for (const statement of sql.matchAll(statements)) {
      if (statement[1]) {
        const tablePolicies = activePolicies.get(statement[2].toLowerCase()) ?? new Map<string, string>();
        tablePolicies.set(statement[1].toLowerCase(), statement[0]);
        activePolicies.set(statement[2].toLowerCase(), tablePolicies);
      } else if (statement[3]) {
        activePolicies.get(statement[4].toLowerCase())?.delete(statement[3].toLowerCase());
      }
    }
    const unscopedPolicies = [...tables].flatMap((table) => [...(activePolicies.get(table)?.entries() ?? [])
      .filter(([, policy]) => !(
        /private\.has_role\s*\(\s*(?:org_id|id)\s*,/i.test(policy)
        || /private\.is_member\s*\(\s*(?:org_id|id)\s*\)/i.test(policy)
        || (table === "user_profiles" && /auth\.uid\s*\(\s*\)/i.test(policy))
      ))
      .map(([name]) => `${table}.${name}`)]);

    expect([...tables].length).toBeGreaterThan(0);
    expect(missingRls, "application tables without RLS").toEqual([]);
    expect(missingPolicy, "application tables without an explicit policy").toEqual([]);
    expect(missingDatabaseTypes, "application tables without a Database TypeScript entry").toEqual([]);
    expect(unscopedPolicies, "active policies without an organization membership or user boundary").toEqual([]);
  });

  it("pins search_path on every SECURITY DEFINER function", async () => {
    const files = await migrationFiles(path.join(process.cwd(), "supabase", "migrations"));
    const sql = (await Promise.all(files.map((file) => readFile(file, "utf8")))).join("\n");
    const starts = [...sql.matchAll(
      /create\s+(?:or\s+replace\s+)?function\s+(?:public|private)\.[\w]+\s*\(/gi,
    )];
    const unsafe: string[] = [];

    for (let index = 0; index < starts.length; index += 1) {
      const start = starts[index].index ?? 0;
      const next = starts[index + 1]?.index ?? sql.length;
      const declaration = sql.slice(start, next).split(/\bas\s+\$[\w]*\$/i, 1)[0];
      if (/security\s+definer/i.test(declaration) && !/set\s+search_path\s*=/i.test(declaration)) {
        unsafe.push(starts[index][0].replace(/\s+/g, " "));
      }
    }

    expect(unsafe, "SECURITY DEFINER functions without a pinned search_path").toEqual([]);
  });
});
