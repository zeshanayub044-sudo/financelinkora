import {Button,Input,Label,Select} from "@/components/ui";
type Category={id:string;code:string;name:string;is_active:boolean};
export function BusinessEntryFilters({action,from,to,category,categories}:{action:string;from:string;to:string;category:string;categories:Category[]}){
 return <form action={action} method="get" className="mb-4 flex flex-wrap items-end gap-3 rounded-xl border border-border bg-slate-50/60 p-4 dark:bg-slate-900/40">
  <div><Label htmlFor={`${action}-from`}>From</Label><Input id={`${action}-from`} type="date" name="from" defaultValue={from}/></div>
  <div><Label htmlFor={`${action}-to`}>To</Label><Input id={`${action}-to`} type="date" name="to" defaultValue={to}/></div>
  <div className="min-w-56"><Label htmlFor={`${action}-category`}>Category</Label><Select id={`${action}-category`} name="category" defaultValue={category}><option value="">All categories</option>{categories.map(c=><option key={c.id} value={c.id}>{c.code} · {c.name}{c.is_active?"":" · Inactive"}</option>)}</Select></div>
  <Button>Apply filters</Button>
 </form>;
}
