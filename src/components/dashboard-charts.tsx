"use client";
import {ResponsiveContainer,AreaChart,Area,BarChart,Bar,CartesianGrid,XAxis,YAxis,Tooltip,Legend,PieChart,Pie,Cell} from "recharts";
import {Card} from "@/components/ui";
import {formatMoney,negateDecimal,sumDecimals} from "@/lib/utils";

const colors=["#2563EB","#06B6D4","#8B5CF6","#F59E0B","#16A34A","#EC4899"];
type MonthPoint={month:string;revenue:number;expenses:number;revenueExact:string;expensesExact:string};
type ExpensePoint={name:string;value:number;amountExact:string};
const compact=(value:number)=>new Intl.NumberFormat("en",{notation:"compact",maximumFractionDigits:1}).format(value);

export function DashboardCharts({monthly,breakdown,currency}:{monthly:MonthPoint[];breakdown:ExpensePoint[];currency:string}){
 return <div className="grid gap-5 xl:grid-cols-3">
  <Card className="p-5 xl:col-span-2"><div className="mb-4"><h2 className="font-semibold">Income vs expenses</h2><p className="mt-1 text-xs text-slate-500">Posted activity by month · last 12 months</p></div><div className="h-[250px]"><ResponsiveContainer width="100%" height="100%"><AreaChart data={monthly}><defs><linearGradient id="rev" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#2563EB" stopOpacity={.2}/><stop offset="100%" stopColor="#2563EB" stopOpacity={0}/></linearGradient></defs><CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--border)"/><XAxis dataKey="month" tickLine={false} axisLine={false} tick={{fontSize:11,fill:"#94a3b8"}}/><YAxis tickLine={false} axisLine={false} tick={{fontSize:10,fill:"#94a3b8"}} tickFormatter={compact}/><Tooltip formatter={(_value,name,item)=>formatMoney(name==="Revenue"?item.payload?.revenueExact??"0":item.payload?.expensesExact??"0",currency)}/><Legend/><Area type="monotone" dataKey="revenue" name="Revenue" stroke="#2563EB" fill="url(#rev)" strokeWidth={2}/><Area type="monotone" dataKey="expenses" name="Expenses" stroke="#06B6D4" fill="#06b6d420" strokeWidth={2}/></AreaChart></ResponsiveContainer></div></Card>
  <Card className="p-5"><div className="mb-2"><h2 className="font-semibold">Expense categories</h2><p className="mt-1 text-xs text-slate-500">Based on posted expense accounts</p></div>{breakdown.length?<div className="h-[265px]"><ResponsiveContainer width="100%" height="100%"><PieChart><Pie data={breakdown} dataKey="value" nameKey="name" innerRadius={62} outerRadius={94} paddingAngle={3}>{breakdown.map((e,i)=><Cell key={e.name} fill={colors[i%colors.length]}/>)}</Pie><Tooltip formatter={(_value,_name,item)=>formatMoney(item.payload?.amountExact??"0",currency)}/><Legend iconType="circle" formatter={value=><span className="text-xs text-slate-500">{value}</span>}/></PieChart></ResponsiveContainer></div>:<div className="grid h-[240px] place-items-center text-center text-sm text-slate-400">No posted expense activity yet.</div>}</Card>
 </div>;
}

export function ProfitChart({monthly,currency}:{monthly:MonthPoint[];currency:string}){
 const data=monthly.map(m=>{const profitExact=sumDecimals([m.revenueExact,negateDecimal(m.expensesExact)]);return {...m,profit:Number(profitExact),profitExact};});
 return <Card className="mt-5 p-5"><div className="mb-4"><h2 className="font-semibold">Monthly profit</h2><p className="mt-1 text-xs text-slate-500">Revenue less expenses · last 12 months of posted entries</p></div><div className="h-[220px]"><ResponsiveContainer width="100%" height="100%"><BarChart data={data}><CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--border)"/><XAxis dataKey="month" tickLine={false} axisLine={false} tick={{fontSize:11,fill:"#94a3b8"}}/><YAxis tickLine={false} axisLine={false} tick={{fontSize:10,fill:"#94a3b8"}} tickFormatter={compact}/><Tooltip formatter={(_value,_name,item)=>formatMoney(item.payload?.profitExact??"0",currency)}/><Bar dataKey="profit" name="Net profit" fill="#2563EB" radius={[5,5,0,0]}/></BarChart></ResponsiveContainer></div></Card>;
}
