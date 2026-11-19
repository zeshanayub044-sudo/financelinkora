"use client";

import {Button} from "@/components/ui";
import {Download,Printer} from "lucide-react";
import {toCsv,type CsvValue} from "@/lib/csv";
import {XlsxExport} from "@/components/xlsx-export";
export function CsvExport({filename,headers,rows}:{filename:string;headers:string[];rows:CsvValue[][]}){
  return <div className="flex flex-wrap gap-2 print:hidden"><Button variant="secondary" onClick={()=>{
    const csv=toCsv(headers,rows);
    const url=URL.createObjectURL(new Blob(["\ufeff",csv],{type:"text/csv;charset=utf-8"}));
    const link=document.createElement("a");link.href=url;link.download=filename;link.click();window.setTimeout(()=>URL.revokeObjectURL(url),1000);
  }}><Download size={15}/>Export CSV</Button><XlsxExport filename={filename} headers={headers} rows={rows}/><Button variant="secondary" onClick={()=>window.print()}><Printer size={15}/>Print / Save PDF</Button></div>;
}
