import {FinancialDocumentDetail} from "@/components/financial-document-detail";
export const metadata={title:"Invoice details"};
export default async function InvoiceDetailPage({params}:{params:Promise<{id:string}>}){
 const {id}=await params;return <FinancialDocumentDetail id={id} type="invoice"/>;
}
