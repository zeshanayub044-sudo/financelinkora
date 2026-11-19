import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";
export function cn(...inputs: ClassValue[]) { return twMerge(clsx(inputs)); }
export function formatMoney(value: number | string, currency = "PKR") {
  const formatter = new Intl.NumberFormat("en-PK", { style: "currency", currency, minimumFractionDigits: 0, maximumFractionDigits: 0 });
  const currencyMinDigits = new Intl.NumberFormat("en-PK", { style: "currency", currency }).resolvedOptions().minimumFractionDigits ?? 2;
  let raw = String(value).trim();
  if (typeof value === "number" && !Number.isFinite(value)) raw = "0";
  const match = /^(-?)(\d+)(?:\.(\d{1,4}))?$/.exec(raw);
  if (!match) return formatter.format(0);
  const wholeMagnitude = BigInt(match[2]);
  const exactZero = wholeMagnitude === BigInt(0) && !/[1-9]/.test(match[3] ?? "");
  const negative = match[1] === "-" && !exactZero;
  const negativeFractionOnly = negative && wholeMagnitude === BigInt(0);
  const parts = formatter.formatToParts(negativeFractionOnly ? -BigInt(1) : negative ? -wholeMagnitude : wholeMagnitude);
  if (negativeFractionOnly) { const integerPart = parts.find(part => part.type === "integer"); if (integerPart) integerPart.value = "0"; }
  const trimmedFraction = (match[3] ?? "").replace(/0+$/, "");
  const fraction = trimmedFraction.padEnd(Math.max(currencyMinDigits,trimmedFraction.length),"0");
  if (fraction) {
    const lastInteger = parts.map(part => part.type).lastIndexOf("integer");
    const decimal = new Intl.NumberFormat("en-PK", { minimumFractionDigits: 1 }).formatToParts(1.1).find(part => part.type === "decimal")?.value ?? ".";
    parts.splice(lastInteger + 1, 0, { type: "decimal", value: decimal }, { type: "fraction", value: fraction });
  }
  return parts.map(part => part.value).join("");
}
function decimalUnits(value:number|string):bigint|null{
  const match=/^(-?)(\d+)(?:\.(\d{1,4}))?$/.exec(String(value).trim());if(!match)return null;
  const units=BigInt(match[2])*BigInt(10_000)+BigInt((match[3]??"").padEnd(4,"0")||"0");return match[1]?-units:units;
}
function unitsText(value:bigint){const zero=BigInt(0);const sign=value<zero?"-":"";const absolute=value<zero?-value:value;const whole=absolute/BigInt(10_000);const fraction=(absolute%BigInt(10_000)).toString().padStart(4,"0").replace(/0+$/g,"");return `${sign}${whole}${fraction?`.${fraction}`:""}`;}
export function isZeroDecimal(value:number|string){return decimalUnits(value)===BigInt(0);}
export function compareDecimals(left:number|string,right:number|string){const a=decimalUnits(left),b=decimalUnits(right);if(a===null||b===null)throw new RangeError("Invalid four-place decimal.");return a<b?-1:a>b?1:0;}
export function negateDecimal(value:number|string){const units=decimalUnits(value);if(units===null)throw new RangeError(`Invalid four-place decimal: ${value}`);return unitsText(-units);}
export function sumDecimals(values: (number|string)[]) {
  const units=values.reduce((total,value)=>{const parsed=decimalUnits(value);if(parsed===null)throw new RangeError(`Invalid four-place decimal: ${value}`);return total+parsed;},BigInt(0));
  return unitsText(units);
}
export function calculatePercent(amount:number|string,rate:number|string){
  const amountMatch=/^(\d{1,16})(?:\.(\d{1,4}))?$/.exec(String(amount).trim());
  const rateMatch=/^(\d{1,3})(?:\.(\d{1,6}))?$/.exec(String(rate).trim());
  if(!amountMatch||!rateMatch)throw new RangeError("Invalid amount or percentage rate.");
  const amountUnits=BigInt(amountMatch[1])*BigInt(10_000)+BigInt((amountMatch[2]??"").padEnd(4,"0")||"0");
  const rateUnits=BigInt(rateMatch[1])*BigInt(1_000_000)+BigInt((rateMatch[2]??"").padEnd(6,"0")||"0");
  const denominator=BigInt(100_000_000);const numerator=amountUnits*rateUnits;
  return unitsText((numerator+denominator/BigInt(2))/denominator);
}
export function trialBalanceTotals(rows:{debit:number|string;credit:number|string}[]){const debit=sumDecimals(rows.map(row=>row.debit));const credit=sumDecimals(rows.map(row=>row.credit));return {debit,credit,balanced:debit===credit};}
export function balanceSheetDifference(assets:number|string,liabilities:number|string,equity:number|string){return sumDecimals([assets,negateDecimal(liabilities),negateDecimal(equity)]);}
export function calculateJournal(lines: {debit: number|string; credit: number|string}[]) {
  const debitUnits=lines.reduce((sum,line)=>{const value=decimalUnits(line.debit);return value===null?null:sum===null?null:sum+value;},BigInt(0) as bigint|null);
  const creditUnits=lines.reduce((sum,line)=>{const value=decimalUnits(line.credit);return value===null?null:sum===null?null:sum+value;},BigInt(0) as bigint|null);
  const debit=debitUnits===null?"0":unitsText(debitUnits);const credit=creditUnits===null?"0":unitsText(creditUnits);
  const zero=BigInt(0);const differenceUnits=debitUnits===null||creditUnits===null?zero:debitUnits-creditUnits;
  const difference=unitsText(differenceUnits);const differenceAbs=unitsText(differenceUnits<zero?-differenceUnits:differenceUnits);
  const balanced=lines.length>=2&&debitUnits!==null&&creditUnits!==null&&debitUnits===creditUnits&&lines.every(l=>{const d=decimalUnits(l.debit),c=decimalUnits(l.credit);return d!==null&&c!==null&&d>=zero&&c>=zero&&(d>zero)!==(c>zero);});
  return {debit,credit,difference,differenceAbs,balanced};
}
