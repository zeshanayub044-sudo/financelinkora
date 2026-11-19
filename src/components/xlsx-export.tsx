"use client";
import {Download} from "lucide-react";
import {Button} from "@/components/ui";
import type {CsvValue} from "@/lib/csv";
import {createXlsx} from "@/lib/xlsx";
export function XlsxExport({filename,headers,rows}:{filename:string;headers:string[];rows:CsvValue[][]}){
 return <Button variant="secondary" onClick={()=>{const bytes=createXlsx(headers,rows),buffer=new ArrayBuffer(bytes.length);new Uint8Array(buffer).set(bytes);const url=URL.createObjectURL(new Blob([buffer],{type:"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"}));const link=document.createElement("a");link.href=url;link.download=filename.replace(/\.csv$/i,".xlsx");link.click();window.setTimeout(()=>URL.revokeObjectURL(url),1000)}}><Download size={15}/>Export Excel</Button>;
}
