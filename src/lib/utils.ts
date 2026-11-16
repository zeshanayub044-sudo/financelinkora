import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";
export function cn(...inputs: ClassValue[]) { return twMerge(clsx(inputs)); }
export function formatMoney(value: number | string, currency = "PKR") {
  const amount = typeof value === "string" ? Number(value) : value;
  return new Intl.NumberFormat("en-PK", { style: "currency", currency, maximumFractionDigits: 2 }).format(Number.isFinite(amount) ? amount : 0);
}
export function calculateJournal(lines: {debit: number|string; credit: number|string}[]) {
  const debit = lines.reduce((sum, line) => sum + Number(line.debit || 0), 0);
  const credit = lines.reduce((sum, line) => sum + Number(line.credit || 0), 0);
  return { debit, credit, difference: Math.round((debit - credit) * 10000) / 10000, balanced: lines.length >= 2 && Math.abs(debit - credit) < 0.00005 && lines.every((l) => (Number(l.debit) > 0) !== (Number(l.credit) > 0)) };
}
