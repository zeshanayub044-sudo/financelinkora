import type {CsvValue} from "@/lib/csv";

const encoder=new TextEncoder();
const xml=(value:CsvValue)=>String(value??"").replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g,"").replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;").replaceAll('"',"&quot;").replaceAll("'","&apos;");
function columnName(index:number){let value="",n=index+1;while(n>0){const remainder=(n-1)%26;value=String.fromCharCode(65+remainder)+value;n=Math.floor((n-1)/26)}return value}
function crc32(bytes:Uint8Array){let crc=0xffffffff;for(const byte of bytes){crc^=byte;for(let bit=0;bit<8;bit++)crc=(crc>>>1)^((crc&1)?0xedb88320:0)}return (crc^0xffffffff)>>>0}
function write16(view:DataView,offset:number,value:number){view.setUint16(offset,value,true)}
function write32(view:DataView,offset:number,value:number){view.setUint32(offset,value>>>0,true)}
function zipStored(files:{name:string;content:string}[]){
 const local:Uint8Array[]=[],central:Uint8Array[]=[];let offset=0;
 for(const file of files){const name=encoder.encode(file.name),data=encoder.encode(file.content),crc=crc32(data),header=new Uint8Array(30+name.length),view=new DataView(header.buffer);
  write32(view,0,0x04034b50);write16(view,4,20);write16(view,6,0x0800);write16(view,8,0);write32(view,14,crc);write32(view,18,data.length);write32(view,22,data.length);write16(view,26,name.length);write16(view,28,0);header.set(name,30);local.push(header,data);
  const directory=new Uint8Array(46+name.length),directoryView=new DataView(directory.buffer);write32(directoryView,0,0x02014b50);write16(directoryView,4,20);write16(directoryView,6,20);write16(directoryView,8,0x0800);write16(directoryView,10,0);write32(directoryView,16,crc);write32(directoryView,20,data.length);write32(directoryView,24,data.length);write16(directoryView,28,name.length);write16(directoryView,30,0);write16(directoryView,32,0);write16(directoryView,34,0);write16(directoryView,36,0);write32(directoryView,38,0);write32(directoryView,42,offset);directory.set(name,46);central.push(directory);offset+=header.length+data.length;
 }
 const directorySize=central.reduce((total,item)=>total+item.length,0),end=new Uint8Array(22),endView=new DataView(end.buffer);write32(endView,0,0x06054b50);write16(endView,8,files.length);write16(endView,10,files.length);write32(endView,12,directorySize);write32(endView,16,offset);
 const result=new Uint8Array(offset+directorySize+end.length);let cursor=0;for(const item of [...local,...central,end]){result.set(item,cursor);cursor+=item.length}return result;
}
export function createXlsx(headers:string[],rows:CsvValue[][]){
 const allRows=[headers,...rows].map((row,rowIndex)=>`<row r="${rowIndex+1}">${row.map((value,index)=>`<c r="${columnName(index)}${rowIndex+1}" t="inlineStr"><is><t xml:space="preserve">${xml(value)}</t></is></c>`).join("")}</row>`).join("");
 const sheet=`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>${allRows}</sheetData></worksheet>`;
 return zipStored([
  {name:"[Content_Types].xml",content:'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>'},
  {name:"_rels/.rels",content:'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'},
  {name:"xl/workbook.xml",content:'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Linkora Report" sheetId="1" r:id="rId1"/></sheets></workbook>'},
  {name:"xl/_rels/workbook.xml.rels",content:'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'},
  {name:"xl/worksheets/sheet1.xml",content:sheet},
 ]);
}
