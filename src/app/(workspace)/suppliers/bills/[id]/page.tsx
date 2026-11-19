import {FinancialDocumentDetail} from "@/components/financial-document-detail";
export const metadata={title:"Bill details"};
export default async function BillDetailPage({params}:{params:Promise<{id:string}>}){
 const {id}=await params;return <FinancialDocumentDetail id={id} type="bill"/>;
}
