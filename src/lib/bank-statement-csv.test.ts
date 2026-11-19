import { describe, expect, it } from "vitest";
import { parseBankStatementCsv } from "@/lib/bank-statement-csv";

describe("parseBankStatementCsv", () => {
  it("preserves signed decimal strings and quoted commas", () => {
    expect(parseBankStatementCsv('date,description,reference,amount\r\n2026-11-01,"Coffee, tea",POS-1,-12.3400\r\n')).toEqual([
      { date: "2026-11-01", description: "Coffee, tea", reference: "POS-1", amount: "-12.3400" },
    ]);
  });
  it("parses escaped quotes and an optional reference column", () => {
    expect(parseBankStatementCsv('date,description,amount\n2026-11-02,"Shop ""A""",1.25')).toEqual([
      { date: "2026-11-02", description: 'Shop "A"', reference: null, amount: "1.25" },
    ]);
  });
  it("rejects missing required headers", () => {
    expect(() => parseBankStatementCsv("date,amount\n2026-11-01,12")).toThrow("headers must include");
  });
  it.each(["2026-02-30", "11/01/2026"]) ("rejects invalid transaction date %s", date => {
    expect(() => parseBankStatementCsv(`date,description,amount\n${date},Sale,10`)).toThrow("real date");
  });
  it.each(["0", "NaN", "1.00001", "1,000.00"]) ("rejects invalid decimal %s", amount => {
    const csvAmount=amount.includes(",")?`"${amount}"`:amount;
    expect(() => parseBankStatementCsv(`date,description,amount\n2026-11-01,Sale,${csvAmount}`)).toThrow("signed amount");
  });
  it("rejects malformed quoted records", () => {
    expect(() => parseBankStatementCsv('date,description,amount\n2026-11-01,"Sale,10')).toThrow("unclosed quoted");
    expect(() => parseBankStatementCsv('date,description,amount\n2026-11-01,"Sale"oops,10')).toThrow("Unexpected text");
  });
});
