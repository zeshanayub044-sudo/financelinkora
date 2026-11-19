import {getWorkspace} from "@/lib/data";
import {Card,EmptyState,PageHeader} from "@/components/ui";
import {DataTable} from "@/components/data-table";
import {CsvExport} from "@/components/csv-export";
import {FixedAssetForm,DepreciationRunForm,FixedAssetDisposalForm} from "@/components/fixed-assets-workspace";
import {formatMoney} from "@/lib/utils";
export const metadata={title:"Fixed assets"};
export default async function FixedAssetsPage(){
 const {org,supabase}=await getWorkspace();if(!org||!supabase)return null;
 const [{data:assets,error:assetError},{data:accounts,error:accountError},{data:entries,error:entryError},{data:runs,error:runError}]=await Promise.all([
  supabase.from("fixed_assets_exact").select("id,org_id,asset_code,name,description,acquisition_date,in_service_date,cost,residual_value,useful_life_months,asset_account_code,accumulated_depreciation_account_code,depreciation_expense_account_code,acquisition_entry_id,status,accumulated_depreciation,net_book_value,created_at").eq("org_id",org.id).order("asset_code"),
  supabase.from("accounts").select("id,code,name,type,reporting_class,cash_flow_class,normal_balance,is_active").eq("org_id",org.id).eq("is_active",true).order("code"),
  supabase.from("journal_entries").select("id,entry_no,entry_date,description").eq("org_id",org.id).eq("status","posted").eq("currency",org.base_currency).eq("exchange_rate",1).order("entry_date",{ascending:false}).limit(100),
  supabase.from("asset_depreciation_runs").select("id,period_start,period_end,status,journal_entry_id,created_at").eq("org_id",org.id).order("period_end",{ascending:false}).limit(24),
 ]);
 const failed=assetError||accountError||entryError||runError;const canManage=["owner","administrator","accountant","finance_manager"].includes(org.role);
 const rows=(assets??[]).map(a=>({...a,cost_display:formatMoney(a.cost,org.base_currency),accumulated_display:formatMoney(a.accumulated_depreciation,org.base_currency),net_book_display:formatMoney(a.net_book_value,org.base_currency),status_label:a.status==="active"?"Active":"Disposed"}));
 const csvRows=rows.map(a=>[a.asset_code,a.name,a.acquisition_date,a.in_service_date,a.cost,a.accumulated_depreciation,a.net_book_value,a.useful_life_months,a.status]);
 return <>
  <PageHeader eyebrow={org.name} title="Fixed assets" description={`Asset register and straight-line depreciation in ${org.base_currency}.`} action={<CsvExport filename="linkora-fixed-assets.csv" headers={["Asset code","Name","Acquisition date","In-service date","Cost","Accumulated depreciation","Net book value","Useful life months","Status"]} rows={csvRows}/>}/>
  {canManage&&<><Card className="mb-5 p-4 md:p-5"><h2 className="mb-3 font-semibold">Register acquired asset</h2><FixedAssetForm orgId={org.id} accounts={(accounts??[]) as never[]} entries={(entries??[]) as never[]}/></Card><Card className="mb-5 p-4 md:p-5"><h2 className="mb-3 font-semibold">Monthly depreciation</h2><p className="mb-3 text-xs text-slate-500">Creates a journal draft for eligible assets. The entry follows maker-checker approval and posting; prior monthly periods must be posted in order.</p><DepreciationRunForm orgId={org.id}/></Card></>}
  {canManage&&assets&&assets.filter(a=>a.status==="active").length>0&&<Card className="mb-5 p-4 md:p-5"><h2 className="mb-3 font-semibold">Dispose an asset</h2><p className="mb-4 text-xs text-slate-500">Disposal removes cost and accumulated depreciation, records proceeds, and recognizes the resulting gain or loss through an approval journal.</p><div className="space-y-3">{assets.filter(a=>a.status==="active").map(a=><FixedAssetDisposalForm key={a.id} orgId={org.id} asset={{id:a.id,asset_code:a.asset_code,name:a.name,net_book_value:a.net_book_value}} accounts={(accounts??[]) as never[]}/>)}</div></Card>}
  {failed ? (
    <Card><EmptyState title="Fixed assets unavailable" description={failed.message}/></Card>
  ) : (
    <Card className="p-4 md:p-5">
      <h2 className="mb-3 font-semibold">Asset register</h2>
      <DataTable rows={rows as unknown as Record<string, unknown>[]} columns={[
        {key:"asset_code",label:"Code"},{key:"name",label:"Asset"},{key:"acquisition_date",label:"Acquired"},
        {key:"in_service_date",label:"In service"},{key:"cost_display",label:`Cost (${org.base_currency})`},
        {key:"accumulated_display",label:"Accumulated depreciation"},{key:"net_book_display",label:"Net book value"},
        {key:"useful_life_months",label:"Life (months)"},{key:"status_label",label:"Status"}
      ]} empty="No fixed assets registered."/>
    </Card>
  )}
  <Card className="mt-5 p-4 md:p-5">
    <h2 className="mb-3 font-semibold">Depreciation runs</h2>
    {runError ? <EmptyState title="Depreciation history unavailable" description={runError.message}/> :
      <DataTable rows={(runs??[]).map(r=>({...r,id:r.id,label:`${r.period_start} – ${r.period_end}`,journal:r.journal_entry_id??"—",status_label:r.status.replaceAll("_"," ")})) as unknown as Record<string, unknown>[]} columns={[
        {key:"label",label:"Period"},{key:"status_label",label:"Status"},{key:"journal",label:"Journal entry"},{key:"created_at",label:"Created"}
      ]} empty="No depreciation runs yet."/>}
  </Card>
  <p className="mt-4 text-xs leading-5 text-slate-400">Only straight-line depreciation is supported, calculated monthly from the in-service month using four-place NUMERIC amounts. Acquisition journals must be posted in the organization’s base currency. Disposal is journal-based and approval-gated; partial-month conventions, foreign currency, impairment, and alternative depreciation methods are not implemented.</p>
 </>;
}
