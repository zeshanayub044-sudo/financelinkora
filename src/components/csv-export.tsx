"use client";

import {Button} from "@/components/ui";
import {Download} from "lucide-react";

type Value=string|number|null|undefined;
function cell(value:Value){
  if(typeof value==="number"&&Number.isFinite(value))return String(value);
  let text=String(value??"");
  if(/^[=+@\-\t\r]/.test(text))text=`'${text}`;
  return `"${text.replaceAll('"','""')}"`;
}
export function CsvExport({filename,headers,rows}:{filename:string;headers:string[];rows:Value[][]}){
  return <Button variant="secondary" onClick={()=>{
    const csv=[headers,...rows].map(row=>row.map(cell).join(",")).join("\r\n");
    const url=URL.createObjectURL(new Blob(["\ufeff",csv],{type:"text/csv;charset=utf-8"}));
    const link=document.createElement("a");link.href=url;link.download=filename;link.click();URL.revokeObjectURL(url);
  }}><Download size={15}/>Export CSV</Button>;
}

