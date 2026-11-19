import {z} from "zod";
export const authCredentialsSchema=z.object({email:z.string().email("Enter a valid email address"),password:z.string().min(8,"Use at least 8 characters")});
export const passwordSchema=z.object({password:z.string().min(8,"Use at least 8 characters")});
const journalAmountSchema=z.string().regex(/^(?:0|[1-9]\d{0,15})(?:\.\d{1,4})?$/,"Enter a valid amount with up to four decimal places.");
const positiveAmount=(value:string)=>/[1-9]/.test(value.replace(".",""));
export const journalLineSchema=z.object({account_id:z.string().uuid(),debit:journalAmountSchema,credit:journalAmountSchema,memo:z.string().max(500).optional()}).refine(x=>positiveAmount(x.debit)!==positiveAmount(x.credit),"Each line needs a non-zero amount on exactly one side.");
export const exchangeRateSchema=z.preprocess(value=>typeof value==="number"?String(value):value,z.string().regex(/^(?:0|[1-9]\d{0,9})(?:\.\d{1,8})?$/,"Enter a positive exchange rate with up to eight decimal places.").refine(value=>/[1-9]/.test(value.replace(".","")),"Exchange rate must be greater than zero."));
const dimensionId=z.string().uuid().or(z.literal("")).nullable().optional();
export const journalDraftSchema=z.object({org_id:z.string().uuid(),entry_date:z.iso.date(),reference:z.string().max(120).optional(),description:z.string().min(2).max(500),currency:z.string().regex(/^[A-Z]{3}$/,"Use a three-letter uppercase currency code."),exchange_rate:exchangeRateSchema,entry_kind:z.enum(["general","opening_balance","income","expense","bank_transfer","bank_deposit","bank_withdrawal","payment","closing","reversal"]).default("general"),lines:z.array(journalLineSchema.extend({department_id:dimensionId,project_id:dimensionId})).min(1)});
export const businessJournalSchema=z.discriminatedUnion("kind",[
  z.object({kind:z.literal("income"),org_id:z.string().uuid(),entry_date:z.iso.date(),description:z.string().trim().min(2).max(500),reference:z.string().trim().max(120).optional(),account_id:z.string().uuid(),asset_account_id:z.string().uuid(),amount:z.string().regex(/^(?:0|[1-9]\d{0,15})(\.\d{1,4})?$/).refine(v=>/[1-9]/.test(v.replace(".","")),"Amount must be greater than zero.")}),
  z.object({kind:z.literal("expense"),org_id:z.string().uuid(),entry_date:z.iso.date(),description:z.string().trim().min(2).max(500),reference:z.string().trim().max(120).optional(),account_id:z.string().uuid(),asset_account_id:z.string().uuid(),amount:z.string().regex(/^(?:0|[1-9]\d{0,15})(\.\d{1,4})?$/).refine(v=>/[1-9]/.test(v.replace(".","")),"Amount must be greater than zero.")}),
  z.object({kind:z.literal("bank_transfer"),org_id:z.string().uuid(),entry_date:z.iso.date(),description:z.string().trim().min(2).max(500),reference:z.string().trim().max(120).optional(),source_account_id:z.string().uuid(),destination_account_id:z.string().uuid(),amount:z.string().regex(/^(?:0|[1-9]\d{0,15})(\.\d{1,4})?$/).refine(v=>/[1-9]/.test(v.replace(".","")),"Amount must be greater than zero.")}).refine(v=>v.source_account_id!==v.destination_account_id,"Choose two different accounts."),
  z.object({kind:z.literal("bank_deposit"),org_id:z.string().uuid(),entry_date:z.iso.date(),description:z.string().trim().min(2).max(500),reference:z.string().trim().max(120).optional(),account_id:z.string().uuid(),asset_account_id:z.string().uuid(),amount:z.string().regex(/^(?:0|[1-9]\d{0,15})(\.\d{1,4})?$/).refine(v=>/[1-9]/.test(v.replace(".","")),"Amount must be greater than zero.")}),
  z.object({kind:z.literal("bank_withdrawal"),org_id:z.string().uuid(),entry_date:z.iso.date(),description:z.string().trim().min(2).max(500),reference:z.string().trim().max(120).optional(),account_id:z.string().uuid(),asset_account_id:z.string().uuid(),amount:z.string().regex(/^(?:0|[1-9]\d{0,15})(\.\d{1,4})?$/).refine(v=>/[1-9]/.test(v.replace(".","")),"Amount must be greater than zero.")})
]);
const budgetLineSchema=z.object({account_id:z.string().uuid(),period_start:z.iso.date(),amount:z.string().regex(/^(?:0|[1-9]\d{0,15})(?:\.\d{1,4})?$/,"Enter a valid amount with up to four decimal places.").refine(v=>/[1-9]/.test(v.replace(".","")),"Budget amount must be greater than zero.")});
export const budgetDraftSchema=z.object({org_id:z.string().uuid(),name:z.string().trim().min(2).max(150),start_date:z.iso.date(),end_date:z.iso.date(),lines:z.array(budgetLineSchema).min(1)}).superRefine((budget,ctx)=>{
  const start=new Date(`${budget.start_date}T00:00:00Z`);const end=new Date(`${budget.end_date}T00:00:00Z`);
  if(start>end||start.getUTCDate()!==1||end.getUTCDate()!==new Date(Date.UTC(end.getUTCFullYear(),end.getUTCMonth()+1,0)).getUTCDate())ctx.addIssue({code:"custom",path:["start_date"],message:"Budgets must cover complete calendar months."});
  const seen=new Set<string>();
  for(const [index,line] of budget.lines.entries()){
    const period=new Date(`${line.period_start}T00:00:00Z`);const key=`${line.account_id}:${line.period_start}`;
    if(period<start||period>end||period.getUTCDate()!==1)ctx.addIssue({code:"custom",path:["lines",index,"period_start"],message:"Choose a month within the budget range."});
    if(seen.has(key))ctx.addIssue({code:"custom",path:["lines",index,"account_id"],message:"Only one amount per account and month is allowed."});
    seen.add(key);
  }
});
export const accountReportingClassSchema=z.object({type:z.enum(["asset","liability","equity","revenue","expense"]),reporting_class:z.enum(["cash","bank","receivable","payable","accumulated_depreciation"]).nullable()}).superRefine((v,ctx)=>{
  if(v.reporting_class&&((v.reporting_class==="payable"&&v.type!=="liability")||(v.reporting_class!=="payable"&&v.type!=="asset")))ctx.addIssue({code:"custom",path:["reporting_class"],message:"Choose a reporting class that matches the account type."});
});
