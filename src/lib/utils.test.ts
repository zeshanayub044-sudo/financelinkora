import { describe, expect, it } from "vitest";
import { calculateJournal, formatMoney } from "./utils";
describe("journal calculations", () => {
  it("balances debits and credits to four decimal places", () => { expect(calculateJournal([{ debit: "10", credit: 0 }, { debit: 0, credit: "10" }])).toMatchObject({ balanced: true, difference: 0 }); });
  it("rejects a one sided or unbalanced entry", () => { expect(calculateJournal([{ debit: 2, credit: 0 }, { debit: 0, credit: 1 }]).balanced).toBe(false); });
  it("formats currency values", () => { expect(formatMoney(0, "PKR")).toContain("0"); });
});
