-- Ratios are derived from posted-ledger summaries, never mutable UI totals.
-- Liquidity coverage uses only accounts explicitly classified for cash/bank/payables.
create or replace function public.financial_ratios_exact(
  p_org uuid,p_from date,p_to date,p_as_of date
) returns table(
  ratio_key text,label text,numerator text,denominator text,value text,unit text
) language plpgsql stable security invoker set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_from is null or p_to is null or p_as_of is null or p_from>p_to or p_as_of<p_to then
    raise exception 'Choose a valid reporting period and balance date';
  end if;
  if not private.has_role(p_org,array['owner','administrator','finance_manager','accountant','approver','auditor','viewer']::public.member_role[]) then
    raise exception 'Not authorized to view this organization';
  end if;
  return query
  with summary as (
    select * from public.financial_summary_exact(p_org,p_from,p_to,p_as_of)
  ), ratio_inputs as (
    select 'debt_to_equity'::text key,'Liabilities to equity'::text label,
      liabilities::numeric numerator,equity::numeric denominator,'x'::text unit from summary
    union all
    select 'net_profit_margin','Net profit margin',profit::numeric*100,income::numeric,'%' from summary
    union all
    select 'return_on_assets','Return on assets',profit::numeric*100,assets::numeric,'%' from summary
    union all
    select 'return_on_equity','Return on equity',profit::numeric*100,equity::numeric,'%' from summary
    union all
    select 'debt_to_assets','Liabilities to assets',liabilities::numeric,assets::numeric,'x' from summary
    union all
    select 'expense_to_income','Expenses to income',expenses::numeric*100,income::numeric,'%' from summary
    union all
    select 'cash_to_payables','Classified cash and bank to payables',
      (cash_balance::numeric+bank_balance::numeric),accounts_payable::numeric,'x' from summary
  )
  select i.key,i.label,i.numerator::text,i.denominator::text,
    case when i.denominator=0 then null else round(i.numerator/nullif(i.denominator,0),4)::text end,
    i.unit
  from ratio_inputs i order by i.key;
end;
$$;

revoke all on function public.financial_ratios_exact(uuid,date,date,date) from public,anon,authenticated;
grant execute on function public.financial_ratios_exact(uuid,date,date,date) to authenticated;
