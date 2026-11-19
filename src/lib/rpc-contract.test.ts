import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { describe, expect, it } from "vitest";

async function filesUnder(directory: string, extension: string): Promise<string[]> {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(entries.map(async (entry) => {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) return filesUnder(fullPath, extension);
    return entry.isFile() && entry.name.endsWith(extension) ? [fullPath] : [];
  }));
  return files.flat();
}

describe("frontend Supabase RPC contract", () => {
  it("defines and grants every literal frontend RPC to authenticated users", async () => {
    const root = process.cwd();
    const sourceFiles = (await filesUnder(path.join(root, "src"), ".ts"))
      .concat(await filesUnder(path.join(root, "src"), ".tsx"));
    const migrationFiles = await filesUnder(path.join(root, "supabase", "migrations"), ".sql");
    const [sources, migrations, databaseTypes] = await Promise.all([
      Promise.all(sourceFiles.map((file) => readFile(file, "utf8"))),
      Promise.all(migrationFiles.map((file) => readFile(file, "utf8"))),
      readFile(path.join(root, "src", "lib", "database.types.ts"), "utf8"),
    ]);
    const frontend = sources.join("\n");
    const sql = migrations.join("\n");
    const rpcNames = new Set([...frontend.matchAll(/\.rpc\(\s*["']([a-z][a-z0-9_]*)["']/gi)].map((match) => match[1]));
    // Include the constrained workflow helper whose RPC name is passed as a union type.
    const workflowNames = frontend.match(/entryRpc\(name:\s*((?:"[a-z][a-z0-9_]*"\s*\|\s*)*"[a-z][a-z0-9_]*")/i)?.[1];
    for (const match of workflowNames?.matchAll(/["']([a-z][a-z0-9_]*)["']/gi) ?? []) rpcNames.add(match[1]);

    const missingFunctions = [...rpcNames].filter((name) => !new RegExp(
      `create\\s+(?:or\\s+replace\\s+)?function\\s+public\\.${name}\\s*\\(`,
      "i",
    ).test(sql));
    const missingGrants = [...rpcNames].filter((name) => !new RegExp(
      `grant\\s+execute\\s+on\\s+function\\s+public\\.${name}\\s*\\([^;]*?\\)\\s+to\\s+authenticated`,
      "is",
    ).test(sql));
    const missingTypes = [...rpcNames].filter((name) => !new RegExp(`\\b${name}\\s*:`).test(databaseTypes));

    expect(missingFunctions, "RPC names without a public SQL function").toEqual([]);
    expect(missingGrants, "RPC functions not explicitly granted to authenticated").toEqual([]);
    expect(missingTypes, "frontend RPCs without Database TypeScript function entries").toEqual([]);
  });
});
