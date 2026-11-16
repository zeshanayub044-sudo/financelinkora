import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";
export function cn(...inputs: ClassValue[]) { return twMerge(clsx(inputs)); }
export function formatMoney(value: number | string, currency = "PKR") {
  const amount = typeof value === "string" ? Number(value) : value;
  return new Intl.NumberFormat("en-PK", { style: "currency", currency, maximumFractionDigits: 2 }).format(Number.isFinite(amount) ? amount : 0);
}
export function calculateJournal(lines: {debit: number|string; credit: number|string}[]) {
  const units=(value:number|string):bigint|null=>{
    const raw=String(value||0).trim();const match=/^(-?)(\d+)(?:\.(\d{1,4}))?$/.exec(raw);if(!match)return null;
    const fraction=(match[3]??"").padEnd(4,"0");const magnitude=BigInt(match[2])*BigInt(10000)+BigInt(fraction||"0");return match[1]? -magnitude:magnitude;
  };
  const debitUnits=lines.reduce((sum,line)=>{const value=units(line.debit);return value===null?null:sum===null?null:sum+value;},BigInt(0) as bigint|null);
  const creditUnits=lines.reduce((sum,line)=>{const value=units(line.credit);return value===null?null:sum===null?null:sum+value;},BigInt(0) as bigint|null);
  const debit=debitUnits===null?NaN:Number(debitUnits)/10_000;const credit=creditUnits===null?NaN:Number(creditUnits)/10_000;
  const difference=debitUnits===null||creditUnits===null?NaN:Number(debitUnits-creditUnits)/10_000;
  const balanced=lines.length>=2&&debitUnits!==null&&creditUnits!==null&&debitUnits===creditUnits&&lines.every(l=>Number(l.debit)>=0&&Number(l.credit)>=0&&(Number(l.debit)>0)!==(Number(l.credit)>0));
  return {debit,credit,difference,balanced};
}

