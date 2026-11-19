import {negateDecimal,sumDecimals} from "@/lib/utils";

type Entry={id:string;entry_no:string|null;entry_date:string;description:string;reference:string|null;status:string;created_at:string};
type EntryLine={entry_id:string;account_id:string};
type LedgerLine={entry_id:string;account_id:string;debit:string;credit:string};
type Account={id:string;code:string;name:string;type:string};

/** Build display rows from organization-scoped entry, line, account, and exact-ledger query results. */
export function buildBusinessEntryHistoryRows(entries:Entry[],lines:EntryLine[],ledger:LedgerLine[],accounts:Account[],categoryType:"revenue"|"expense"){
 const accountsById=new Map(accounts.map(account=>[account.id,account]));
 const categoriesByEntry=new Map<string,Set<string>>();
 for(const line of lines){
  const account=accountsById.get(line.account_id);if(account?.type!==categoryType)continue;
  const values=categoriesByEntry.get(line.entry_id)??new Set<string>();values.add(`${account.code} · ${account.name}`);categoriesByEntry.set(line.entry_id,values);
 }
 const amountsByEntry=new Map<string,string[]>();
 for(const line of ledger){
  if(accountsById.get(line.account_id)?.type!==categoryType)continue;
  const values=amountsByEntry.get(line.entry_id)??[];
  values.push(categoryType==="revenue"?sumDecimals([line.credit,negateDecimal(line.debit)]):sumDecimals([line.debit,negateDecimal(line.credit)]));
  amountsByEntry.set(line.entry_id,values);
 }
 return entries.map(entry=>({
  ...entry,
  entry_no:entry.entry_no??"Draft · unnumbered",
  category:[...(categoriesByEntry.get(entry.id)??[])].sort().join(", ")||"—",
  amount:amountsByEntry.has(entry.id)?sumDecimals(amountsByEntry.get(entry.id)!):"—",
 }));
}

export function filterEntriesByCategory<T extends {id:string}>(entries:T[],lines:EntryLine[],categoryId:string){
 if(!categoryId)return entries;
 const matching=new Set(lines.filter(line=>line.account_id===categoryId).map(line=>line.entry_id));
 return entries.filter(entry=>matching.has(entry.id));
}
