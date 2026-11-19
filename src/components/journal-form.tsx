"use client";

import {useState} from "react";
import {useRouter} from "next/navigation";
import {useFieldArray,useForm} from "react-hook-form";
import {zodResolver} from "@hookform/resolvers/zod";
import {z} from "zod";
import {Plus,Trash2} from "lucide-react";
import {Button,Input,Label,Select} from "@/components/ui";
import {calculateJournal,formatMoney} from "@/lib/utils";
import {exchangeRateSchema} from "@/lib/validation";
import {createJournalAction,updateJournalAction} from "@/app/(workspace)/actions";

const schema=z.object({
  entry_date:z.string().min(1,"Choose an entry date"),
  reference:z.string().max(120),
  description:z.string().min(2,"Add an entry description").max(500),
  currency:z.string().regex(/^[A-Z]{3}$/),
  exchange_rate:exchangeRateSchema,
  entry_kind:z.enum(["general","opening_balance","income","expense","bank_transfer","payment","closing","reversal"]),
  lines:z.array(z.object({
    account_id:z.string().uuid("Choose an account"),
    department_id:z.string().uuid().or(z.literal("")),
    project_id:z.string().uuid().or(z.literal("")),
    debit:z.string().regex(/^(?:0|[1-9]\d{0,15})(?:\.\d{1,4})?$/,"Use up to four decimal places"),
    credit:z.string().regex(/^(?:0|[1-9]\d{0,15})(?:\.\d{1,4})?$/,"Use up to four decimal places"),
    memo:z.string().max(500),
  }).refine(x=>(/[1-9]/.test(x.debit.replace(".","")))!==(/[1-9]/.test(x.credit.replace(".",""))),"Enter an amount on one side only"))
    .min(1,"At least one journal line is required"),
});
type Values=z.input<typeof schema>;
type Output=z.output<typeof schema>;
type Account={id:string;code:string;name:string;type:string};
type Dimension={id:string;code:string;name:string};
type InitialValues=Partial<Omit<Output,"lines">>&{lines?:{account_id:string;debit:number|string;credit:number|string;memo:string|null;department_id?:string|null;project_id?:string|null}[]};

export function JournalForm({orgId,currency,accounts,departments=[],projects=[],entryId,initialValues,rejectionReason,allowOpeningBalance=false}:{orgId:string;currency:string;accounts:Account[];departments?:Dimension[];projects?:Dimension[];entryId?:string;initialValues?:InitialValues;rejectionReason?:string|null;allowOpeningBalance?:boolean}){
  const router=useRouter();const [message,setMessage]=useState("");const [busy,setBusy]=useState(false);
  const {register,control,watch,handleSubmit,setValue,formState:{errors}}=useForm<Values,unknown,Output>({
    resolver:zodResolver(schema),
    defaultValues:{
      entry_date:initialValues?.entry_date??new Date().toISOString().slice(0,10),
      reference:initialValues?.reference??"",
      description:initialValues?.description??"",
      currency:initialValues?.currency??currency,
      exchange_rate:String(initialValues?.exchange_rate??1),
      entry_kind:initialValues?.entry_kind??"general",
      lines:initialValues?.lines?.map(line=>({account_id:line.account_id,department_id:line.department_id??"",project_id:line.project_id??"",debit:String(line.debit),credit:String(line.credit),memo:line.memo??""}))
        ??[{account_id:"",department_id:"",project_id:"",debit:"0",credit:"0",memo:""},{account_id:"",department_id:"",project_id:"",debit:"0",credit:"0",memo:""}],
    },
  });
  const {fields,append,remove}=useFieldArray({control,name:"lines"});
  // react-hook-form's watch() keeps debit and credit totals current while typing.
  // eslint-disable-next-line react-hooks/incompatible-library
  const lines=watch("lines");
  const transactionCurrency=watch("currency")||currency;
  const entryKind=watch("entry_kind");
  const selectableAccounts=entryKind==="opening_balance"?accounts.filter(a=>["asset","liability","equity"].includes(a.type)):entryKind==="income"?accounts.filter(a=>["asset","revenue"].includes(a.type)):entryKind==="expense"?accounts.filter(a=>["asset","expense"].includes(a.type)):entryKind==="bank_transfer"?accounts.filter(a=>a.type==="asset"):accounts;
  const totals=calculateJournal((lines??[]) as {debit:number|string;credit:number|string}[]);
  const onSubmit=handleSubmit(async(value)=>{
    setBusy(true);setMessage("");
    try {
      const input={...value,org_id:orgId};
      const result=entryId?await updateJournalAction(entryId,input):await createJournalAction(input);
      if("error" in result)setMessage(result.error??"Unable to save draft.");
      else{setMessage("Draft saved. Balance it before submitting for review.");router.push(entryId?`/journal-entries/${entryId}`:"/journal-entries");}
    } catch {
      setMessage("Unable to save draft because the request failed. Your changes are still in this form; please try again.");
    } finally {
      setBusy(false);
    }
  });
  return <form onSubmit={onSubmit} className="space-y-6">
    {rejectionReason&&<div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800"><strong>Returned for correction:</strong> {rejectionReason}</div>}
    <div className="grid gap-4 sm:grid-cols-2">
      <div><Label htmlFor="entry_date">Entry date</Label><Input type="date" id="entry_date" {...register("entry_date")}/>{errors.entry_date&&<p className="mt-1 text-xs text-red-600">{errors.entry_date.message}</p>}</div>
      <div><Label htmlFor="reference">Reference</Label><Input id="reference" placeholder="Optional document reference" {...register("reference")}/></div>
      <div className="sm:col-span-2"><Label htmlFor="description">Description</Label><Input id="description" placeholder="What is this journal entry for?" {...register("description")}/>{errors.description&&<p className="mt-1 text-xs text-red-600">{errors.description.message}</p>}</div>
      {allowOpeningBalance&&!entryId&&<div><Label htmlFor="entry_kind">Entry type</Label><Select id="entry_kind" {...register("entry_kind",{onChange:()=>fields.forEach((_,index)=>setValue(`lines.${index}.account_id`,""))})}><option value="general">Standard journal entry</option><option value="opening_balance">Opening balance</option></Select><p className="mt-1 text-[10px] text-slate-500">Opening balances are restricted to balance sheet accounts and require owner or finance manager authorization.</p></div>}
      <div><Label htmlFor="currency">Transaction currency</Label><Input id="currency" placeholder={currency} maxLength={3} readOnly={Boolean(entryId)} autoCapitalize="characters" {...register("currency")} onChange={event=>{const value=event.currentTarget.value.trim().toUpperCase();event.currentTarget.value=value;setValue("currency",value,{shouldValidate:true});}}/><p className="mt-1 text-[10px] text-slate-500">Enter a three-letter ISO code. Use {currency} for base-currency entries.</p></div>
      <div><Label htmlFor="exchange_rate">Exchange rate</Label><Input id="exchange_rate" inputMode="decimal" readOnly={Boolean(entryId)} {...register("exchange_rate")}/><p className="mt-1 text-[10px] text-slate-500">Base-currency units per 1 transaction-currency unit. Enter a manually approved rate; base-currency entries use 1.</p></div>
    </div>
    <div className="overflow-x-auto rounded-xl border border-border"><table className="w-full min-w-[1120px] text-left text-sm">
      <thead className="bg-slate-50 text-[11px] uppercase tracking-wide text-slate-500"><tr><th className="p-3">Account</th><th className="p-3">Department</th><th className="p-3">Project</th><th className="p-3">Description</th><th className="p-3">Debit</th><th className="p-3">Credit</th><th className="p-3"/></tr></thead>
      <tbody>{fields.map((field,index)=><tr key={field.id} className="border-t border-border">
        <td className="w-[27%] p-2"><Select aria-label={`Account line ${index+1}`} {...register(`lines.${index}.account_id`)}><option value="">Select account</option>{selectableAccounts.map(account=><option key={account.id} value={account.id}>{account.code} · {account.name}</option>)}</Select>{errors.lines?.[index]?.account_id&&<small className="text-red-600">{errors.lines[index]?.account_id?.message}</small>}</td>
        <td className="p-2"><Select aria-label={`Department line ${index+1}`} {...register(`lines.${index}.department_id`)}><option value="">No department</option>{departments.map(d=><option key={d.id} value={d.id}>{d.code} · {d.name}</option>)}</Select></td>
        <td className="p-2"><Select aria-label={`Project line ${index+1}`} {...register(`lines.${index}.project_id`)}><option value="">No project</option>{projects.map(p=><option key={p.id} value={p.id}>{p.code} · {p.name}</option>)}</Select></td>
        <td className="p-2"><Input aria-label={`Line description ${index+1}`} placeholder="Memo" {...register(`lines.${index}.memo`)}/></td>
        <td className="p-2"><Input aria-label={`Debit line ${index+1}`} inputMode="decimal" {...register(`lines.${index}.debit`)}/></td>
        <td className="p-2"><Input aria-label={`Credit line ${index+1}`} inputMode="decimal" {...register(`lines.${index}.credit`)}/></td>
        <td className="p-2"><Button type="button" variant="ghost" aria-label={`Remove line ${index+1}`} disabled={fields.length<=1} onClick={()=>remove(index)}><Trash2 size={16}/></Button></td>
      </tr>)}</tbody>
      <tfoot className="border-t border-border bg-slate-50 font-semibold"><tr><td colSpan={4} className="p-3 text-right">Total ({transactionCurrency})</td><td className="p-3">{formatMoney(totals.debit,transactionCurrency)}</td><td className="p-3">{formatMoney(totals.credit,transactionCurrency)}</td><td/></tr>
        <tr><td colSpan={5} className="p-3 text-right text-xs text-slate-500">Difference</td><td colSpan={2} className={totals.balanced?"p-3 text-xs text-green-700":"p-3 text-xs text-amber-700"}>{formatMoney(totals.differenceAbs,transactionCurrency)}{totals.balanced?" · Balanced":" · Balance required before submission"}</td></tr>
      </tfoot>
    </table></div>
    {errors.lines?.root&&<p className="text-sm text-red-600">{errors.lines.root.message}</p>}
    <div className="flex flex-wrap items-center justify-between gap-3"><Button type="button" variant="secondary" onClick={()=>append({account_id:"",department_id:"",project_id:"",debit:"0",credit:"0",memo:""})}><Plus size={16}/>Add line</Button><Button type="submit" disabled={busy}>{busy?"Saving draft…":entryId?"Save draft changes":"Save draft"}</Button></div>
    {message&&<p role="status" className="rounded-lg bg-blue-50 p-3 text-sm text-blue-900">{message}</p>}
    <p className="text-xs leading-5 text-slate-400">Draft amounts are entered in transaction currency and translated to functional currency at the stated manual rate when saved. Rates are not fetched automatically; foreign-currency revaluation and realized/unrealized exchange gains or losses are not implemented. Drafts can be saved incomplete, but database submission, approval, and posting require exact balance in both currencies.</p>
  </form>;
}
