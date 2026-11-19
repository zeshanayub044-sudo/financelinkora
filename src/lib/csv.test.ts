import { describe, expect, it } from "vitest";
import { toCsv } from "./csv";

describe("CSV export", () => {
  it("preserves signed exact decimal amounts", () => {
    expect(toCsv(["amount"], [["-1234567890123456.7890"]])).toBe('"amount"\r\n"-1234567890123456.7890"');
  });

  it("neutralizes formula-like text and quotes embedded quotes", () => {
    expect(toCsv(["description"], [["=SUM(A1:A2)"], ["-1+HYPERLINK(\"https://evil\")"]]))
      .toBe('"description"\r\n"\'=SUM(A1:A2)"\r\n"\'-1+HYPERLINK(""https://evil"")"');
  });
});
