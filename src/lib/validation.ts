import {z} from "zod";
export const authCredentialsSchema=z.object({email:z.string().email("Enter a valid email address"),password:z.string().min(8,"Use at least 8 characters")});
export const passwordSchema=z.object({password:z.string().min(8,"Use at least 8 characters")});
export const journalLineSchema=z.object({account_id:z.string().uuid(),debit:z.number().nonnegative(),credit:z.number().nonnegative(),memo:z.string().max(500).optional()}).refine(x=>(x.debit>0)!==(x.credit>0),"Each line needs a non-zero amount on exactly one side.");
export const journalDraftSchema=z.object({org_id:z.string().uuid(),entry_date:z.string(),reference:z.string().max(120).optional(),description:z.string().min(2).max(500),currency:z.string().length(3),exchange_rate:z.number().positive(),lines:z.array(journalLineSchema).min(2)}).refine(x=>Math.abs(x.lines.reduce((s,l)=>s+l.debit,0)-x.lines.reduce((s,l)=>s+l.credit,0))<0.00005,"Debits and credits must balance to four decimal places.");
