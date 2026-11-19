import {describe,expect,it} from "vitest";
import {buildBusinessEntryHistoryRows,filterEntriesByCategory} from "./business-entry-history";

const accounts=[{id:"rev-a",code:"4000",name:"Services",type:"revenue"},{id:"rev-b",code:"4100",name:"Products",type:"revenue"},{id:"exp",code:"5000",name:"Supplies",type:"expense"}];
const entries=[{id:"posted",entry_no:"JE-1",entry_date:"2026-01-01",description:"Sale",reference:null,status:"posted",created_at:"2026-01-01T00:00:00Z"},{id:"draft",entry_no:null,entry_date:"2026-01-02",description:"Draft expense",reference:null,status:"draft",created_at:"2026-01-02T00:00:00Z"}];
describe("income and expense history calculations",()=>{
 it("sums posted revenue with exact decimal arithmetic and lists its categories",()=>{
  const rows=buildBusinessEntryHistoryRows(entries.slice(0,1),[{entry_id:"posted",account_id:"rev-b"},{entry_id:"posted",account_id:"rev-a"}],
   [{entry_id:"posted",account_id:"rev-a",debit:"0",credit:"9007199254740993.0001"},{entry_id:"posted",account_id:"rev-b",debit:"0",credit:"0.0004"}],accounts,"revenue");
  expect(rows[0]).toMatchObject({category:"4000 · Services, 4100 · Products",amount:"9007199254740993.0005"});
 });
 it("calculates expenses as debit less credit and never invents draft amounts",()=>{
  const rows=buildBusinessEntryHistoryRows(entries,[{entry_id:"posted",account_id:"exp"},{entry_id:"draft",account_id:"exp"}],
   [{entry_id:"posted",account_id:"exp",debit:"42.75",credit:"0.25"}],accounts,"expense");
  expect(rows.map(row=>row.amount)).toEqual(["42.5","—"]);
  expect(rows[1].entry_no).toBe("Draft · unnumbered");
 });
 it("filters history by the selected journal-line category",()=>{
  expect(filterEntriesByCategory(entries,[{entry_id:"posted",account_id:"rev-a"}],"rev-a").map(e=>e.id)).toEqual(["posted"]);
  expect(filterEntriesByCategory(entries,[],"")).toHaveLength(2);
 });
});
