-- Statement of changes in equity from posted/reversed functional-currency ledger data.
-- The cumulative P&L row carries unclosed earnings, matching the balance-sheet
-- treatment already used by balance_sheet_exact.
create or replace function public.statement_of_changes_in_equity_exact(
  p_org uuid,p_from date,p_to date
) returns table(
  line_type text,account_id uuid,code text,name text,
  opening_balance text,period_movement text,closing_balance text
) language plpgsql stable security invoker set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_from is null or p_to is null or p_from>p_to then raise exception 'Choose a valid equity reporting date range'; end if;
  if not private.has_role(p_org,array['owner','administrator','finance_manager','accountant','approver','auditor','viewer']::public.member_role[]) then
    raise exception 'Not authorized to view this organization';
  end if;

  return query
  with equity_accounts as (
    select a.id,a.code,a.name,
      coalesce(sum(l.base_credit-l.base_debit) filter(where e.entry_date<p_from),0) opening,
      coalesce(sum(l.base_credit-l.base_debit) filter(where e.entry_date between p_from and p_to),0) movement,
      coalesce(sum(l.base_credit-l.base_debit) filter(where e.entry_date<=p_to),0) closing
    from public.accounts a
    left join public.journal_lines l on l.org_id=a.org_id and l.account_id=a.id
    left join public.journal_entries e on e.org_id=l.org_id and e.id=l.entry_id
      and e.status in ('posted','reversed') and e.entry_date<=p_to
    where a.org_id=p_org and a.type='equity'
    group by a.id,a.code,a.name
  ), earnings as (
    select
      coalesce(sum(l.base_credit-l.base_debit) filter(where e.entry_date<p_from),0) opening,
      coalesce(sum(l.base_credit-l.base_debit) filter(where e.entry_date between p_from and p_to),0) movement,
      coalesce(sum(l.base_credit-l.base_debit) filter(where e.entry_date<=p_to),0) closing
    from public.accounts a
    join public.journal_lines l on l.org_id=a.org_id and l.account_id=a.id
    join public.journal_entries e on e.org_id=l.org_id and e.id=l.entry_id
    where a.org_id=p_org and a.type in ('revenue','expense')
      and e.status in ('posted','reversed') and e.entry_date<=p_to
  )
  select 'equity_account'::text,ea.id,ea.code,ea.name,ea.opening::text,ea.movement::text,ea.closing::text
  from equity_accounts ea
  union all
  select 'undistributed_earnings'::text,null::uuid,null::text,'Undistributed earnings (unclosed P&L)',
    en.opening::text,en.movement::text,en.closing::text from earnings en
  order by 1,3 nulls last;
end;
$$;

revoke all on function public.statement_of_changes_in_equity_exact(uuid,date,date) from public,anon,authenticated;
grant execute on function public.statement_of_changes_in_equity_exact(uuid,date,date) to authenticated;
