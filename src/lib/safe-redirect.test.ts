import { describe, expect, it } from "vitest";
import { safeInternalPath } from "./safe-redirect";

describe("safeInternalPath", () => {
  it("preserves a same-origin path, query, and hash", () => {
    expect(safeInternalPath("/journal-entries/new?from=login#lines")).toBe("/journal-entries/new?from=login#lines");
  });

  it.each([
    "https://attacker.example/path",
    "//attacker.example/path",
    "/\\attacker.example/path",
    "",
    null,
    undefined,
  ])("uses the safe fallback for an invalid target: %s", (value) => {
    expect(safeInternalPath(value)).toBe("/dashboard");
  });
});
