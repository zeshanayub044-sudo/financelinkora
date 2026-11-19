export type BankStatementCsvRow = { date: string; description: string; reference: string | null; amount: string };

function recordsFromCsv(input: string) {
  const records: string[][] = [];
  let record: string[] = [];
  let value = "";
  let quoted = false;
  let closedQuote = false;
  for (let i = 0; i < input.length; i++) {
    const char = input[i];
    if (quoted) {
      if (char === '"' && input[i + 1] === '"') { value += '"'; i++; }
      else if (char === '"') { quoted = false; closedQuote = true; }
      else value += char;
    } else if (char === '"') {
      if (value.length || closedQuote) throw new Error("A quote must begin at the start of a CSV field.");
      quoted = true;
    } else if (char === ",") {
      record.push(value); value = ""; closedQuote = false;
    } else if (char === "\n" || char === "\r") {
      if (char === "\r" && input[i + 1] === "\n") i++;
      record.push(value); value = ""; closedQuote = false;
      if (record.some(cell => cell.trim() !== "")) records.push(record);
      record = [];
    } else {
      if (closedQuote) throw new Error("Unexpected text after a quoted CSV field.");
      value += char;
    }
  }
  if (quoted) throw new Error("The CSV contains an unclosed quoted field.");
  record.push(value);
  if (record.some(cell => cell.trim() !== "")) records.push(record);
  return records;
}

function validIsoDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

export function parseBankStatementCsv(csv: string): BankStatementCsvRow[] {
  if (!csv.trim()) throw new Error("Choose a non-empty CSV file.");
  if (csv.length > 2_000_000) throw new Error("CSV file must be 2 MB or smaller.");
  const [header, ...records] = recordsFromCsv(csv);
  if (!header) throw new Error("The CSV needs a header row.");
  const headers = header.map((cell,index) => `${index===0?cell.replace(/^\uFEFF/,""):cell}`.trim().toLowerCase());
  if (headers.some(name=>!name)) throw new Error("CSV headers must not be blank.");
  const dateIndex = headers.indexOf("date");
  const descriptionIndex = headers.indexOf("description");
  const amountIndex = headers.indexOf("amount");
  const referenceIndex = headers.indexOf("reference");
  if (dateIndex < 0 || descriptionIndex < 0 || amountIndex < 0) throw new Error("CSV headers must include date, description, and amount; reference is optional.");
  if (new Set(headers).size !== headers.length) throw new Error("CSV headers must not be duplicated.");
  if (records.length < 1 || records.length > 5000) throw new Error("CSV must contain between 1 and 5000 transactions.");
  return records.map((row, index) => {
    if (row.length !== headers.length) throw new Error(`CSV row ${index + 2} has a different number of fields than the header.`);
    const date = row[dateIndex].trim();
    const description = row[descriptionIndex].trim();
    const reference = referenceIndex < 0 ? null : row[referenceIndex].trim() || null;
    const amount = row[amountIndex].trim();
    if (!validIsoDate(date)) throw new Error(`CSV row ${index + 2} needs a real date in YYYY-MM-DD format.`);
    if (!description || description.length > 500) throw new Error(`CSV row ${index + 2} needs a description of at most 500 characters.`);
    if (reference && reference.length > 120) throw new Error(`CSV row ${index + 2} reference must be at most 120 characters.`);
    if (!/^-?(?:0|[1-9]\d{0,15})(?:\.\d{1,4})?$/.test(amount) || !/[1-9]/.test(amount)) throw new Error(`CSV row ${index + 2} needs a non-zero signed amount with at most four decimal places.`);
    return { date, description, reference, amount };
  });
}
