import {describe,expect,it} from "vitest";
import {createXlsx} from "@/lib/xlsx";

function storedEntries(bytes:Uint8Array){
  const view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength),decoder=new TextDecoder();const entries=new Map<string,string>();let offset=0;
  while(offset+4<=bytes.length&&view.getUint32(offset,true)===0x04034b50){const size=view.getUint32(offset+18,true),nameLength=view.getUint16(offset+26,true),extraLength=view.getUint16(offset+28,true),name=decoder.decode(bytes.slice(offset+30,offset+30+nameLength)),start=offset+30+nameLength+extraLength;entries.set(name,decoder.decode(bytes.slice(start,start+size)));offset=start+size;}
  return {entries,offset,view};
}

describe("accounting spreadsheet export",()=>{
  it("creates an XLSX ZIP package with its workbook parts",()=>{
    const bytes=createXlsx(["Account","Balance"],[["Cash","9007199254740993.0001"]]);const {entries,offset,view}=storedEntries(bytes);
    expect(entries.has("[Content_Types].xml")).toBe(true);
    expect(entries.has("xl/workbook.xml")).toBe(true);
    expect(view.getUint32(offset,true)).toBe(0x02014b50);
    expect(view.getUint32(bytes.length-22,true)).toBe(0x06054b50);
  });
  it("preserves exact financial text and treats user values as text",()=>{
    const {entries}=storedEntries(createXlsx(["Account","Balance"],[["<script>=SUM(1,2)","9007199254740993.0001"]]));const sheet=entries.get("xl/worksheets/sheet1.xml")??"";
    expect(sheet).toContain("&lt;script&gt;=SUM(1,2)");
    expect(sheet).toContain("9007199254740993.0001");
    expect(sheet).not.toContain("<f>");
    expect(sheet).toContain('t="inlineStr"');
  });
});
