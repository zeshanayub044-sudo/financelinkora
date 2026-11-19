export type CsvValue = string | number | null | undefined;

function cell(value: CsvValue) {
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  let text = String(value ?? "");
  // Signed, plain decimal values are accounting data (including negative
  // balances), not formulas. Preserve their exact text in the exported file.
  const isDecimal = /^-?\d+(?:\.\d+)?$/.test(text);
  if (!isDecimal && /^[=+@\-\t\r]/.test(text)) text = `'${text}`;
  return `"${text.replaceAll('"', '""')}"`;
}

export function toCsv(headers: string[], rows: CsvValue[][]) {
  return [headers, ...rows].map(row => row.map(cell).join(",")).join("\r\n");
}
