import { describe, expect, it } from "vitest";
import { accountReportingClassSchema, authCredentialsSchema, budgetDraftSchema, businessJournalSchema, exchangeRateSchema, journalDraftSchema } from "./validation";

const org = "00000000-0000-4000-8000-000000000001";
const accountA = "00000000-0000-4000-8000-000000000002";
const accountB = "00000000-0000-4000-8000-000000000003";
const validJournal = { org_id: org, entry_date: "2026-11-16", description: "Office supplies", currency: "PKR", exchange_rate: 1, lines: [{ account_id: accountA, debit: "100", credit: "0" }, { account_id: accountB, debit: "0", credit: "100" }] };

describe("form validation", () => {
  it("accepts valid email and password", () => expect(authCredentialsSchema.safeParse({ email: "finance@example.com", password: "secure-password" }).success).toBe(true));
  it("rejects invalid email and short passwords", () => expect(authCredentialsSchema.safeParse({ email: "bad", password: "123" }).success).toBe(false));
  it("accepts balanced journal entries", () => expect(journalDraftSchema.safeParse(validJournal).success).toBe(true));
  it("accepts a manual foreign-currency rate with eight decimal places",()=>{
    const parsed=journalDraftSchema.safeParse({...validJournal,currency:"EUR",exchange_rate:"1.23456789"});
    expect(parsed.success).toBe(true);
    if(parsed.success)expect(parsed.data.exchange_rate).toBe("1.23456789");
  });
  it("rejects malformed currency codes and invalid manual rates",()=>{
    expect(journalDraftSchema.safeParse({...validJournal,currency:"eur"}).success).toBe(false);
    expect(exchangeRateSchema.safeParse("1.123456789").success).toBe(false);
    expect(exchangeRateSchema.safeParse("0").success).toBe(false);
    expect(exchangeRateSchema.safeParse("Infinity").success).toBe(false);
  });
  it("accepts the controlled opening balance entry kind", () => expect(journalDraftSchema.safeParse({ ...validJournal, entry_kind: "opening_balance" }).success).toBe(true));
  it("preserves large decimal strings and rejects numeric special values", () => {
    expect(journalDraftSchema.safeParse({ ...validJournal, lines: [{ account_id: accountA, debit: "9007199254740993.0001", credit: "0" }, { account_id: accountB, debit: "0", credit: "9007199254740993" }] }).success).toBe(true);
    expect(journalDraftSchema.safeParse({ ...validJournal, lines: [{ account_id: accountA, debit: "NaN", credit: "0" }] }).success).toBe(false);
    expect(journalDraftSchema.safeParse({ ...validJournal, lines: [{ account_id: accountA, debit: "Infinity", credit: "0" }] }).success).toBe(false);
  });
  it("allows an unbalanced draft to be saved for later correction", () => expect(journalDraftSchema.safeParse({ ...validJournal, lines: [...validJournal.lines.slice(0, 1), { ...validJournal.lines[1], credit: "99" }] }).success).toBe(true));
  it("rejects a line with both debit and credit", () => expect(journalDraftSchema.safeParse({ ...validJournal, lines: [{ ...validJournal.lines[0], credit: "100" }, validJournal.lines[1]] }).success).toBe(false));
  it("validates positive amounts with at most four decimals", () => {
    const input = { kind: "income", org_id: org, entry_date: "2026-11-16", description: "Client receipt", account_id: accountA, asset_account_id: accountB, amount: "100.125" };
    expect(businessJournalSchema.safeParse(input).success).toBe(true);
    expect(businessJournalSchema.safeParse({ ...input, amount: "0" }).success).toBe(false);
    expect(businessJournalSchema.safeParse({ ...input, amount: "1.12345" }).success).toBe(false);
    expect(businessJournalSchema.safeParse({ ...input, amount: "10000000000000000" }).success).toBe(false);
  });
  it("prevents transfers between the same asset account", () => expect(businessJournalSchema.safeParse({ kind: "bank_transfer", org_id: org, entry_date: "2026-11-16", description: "Move cash", source_account_id: accountA, destination_account_id: accountA, amount: "25" }).success).toBe(false));
  it("accepts balanced bank deposit and withdrawal inputs with explicit offset accounts",()=>{
    const movement={org_id:org,entry_date:"2026-11-16",description:"Bank movement",account_id:accountA,asset_account_id:accountB,amount:"25.00"};
    expect(businessJournalSchema.safeParse({...movement,kind:"bank_deposit"}).success).toBe(true);
    expect(businessJournalSchema.safeParse({...movement,kind:"bank_withdrawal"}).success).toBe(true);
  });
  it("accepts a monthly budget line in a complete-year budget",()=>expect(budgetDraftSchema.safeParse({org_id:org,name:"FY 2026 Plan",start_date:"2026-01-01",end_date:"2026-12-31",lines:[{account_id:accountA,period_start:"2026-02-01",amount:"1250.4500"}]}).success).toBe(true));
  it("rejects partial periods, duplicate account-month lines, and out-of-range months",()=>{
    const budget={org_id:org,name:"FY 2026 Plan",start_date:"2026-01-01",end_date:"2026-12-31",lines:[{account_id:accountA,period_start:"2026-02-01",amount:"100"}]};
    expect(budgetDraftSchema.safeParse({...budget,end_date:"2026-12-30"}).success).toBe(false);
    expect(budgetDraftSchema.safeParse({...budget,lines:[...budget.lines,{...budget.lines[0]}]}).success).toBe(false);
    expect(budgetDraftSchema.safeParse({...budget,lines:[{...budget.lines[0],period_start:"2027-01-01"}]}).success).toBe(false);
  });
  it("requires dashboard classifications to match the account category",()=>{
    expect(accountReportingClassSchema.safeParse({type:"asset",reporting_class:"bank"}).success).toBe(true);
    expect(accountReportingClassSchema.safeParse({type:"liability",reporting_class:"payable"}).success).toBe(true);
    expect(accountReportingClassSchema.safeParse({type:"asset",reporting_class:"accumulated_depreciation"}).success).toBe(true);
    expect(accountReportingClassSchema.safeParse({type:"expense",reporting_class:"cash"}).success).toBe(false);
    expect(accountReportingClassSchema.safeParse({type:"asset",reporting_class:"payable"}).success).toBe(false);
  });
});
