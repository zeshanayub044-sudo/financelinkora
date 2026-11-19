-- Transactions may carry an explicitly entered exchange rate. Rates remain
-- journal-specific and are audit-logged with the journal header; there is no
-- automatic exchange-rate feed or revaluation process.
create or replace function public.journal_exchange_rate_exact(p_entry uuid)
returns table(currency text,exchange_rate text)
language sql stable security invoker set search_path = ''
as $$
  select e.currency::text,e.exchange_rate::text
  from public.journal_entries e
  where e.id=p_entry and private.has_role(e.org_id,
    array['owner','administrator','finance_manager','accountant','approver','auditor','viewer']::public.member_role[])
$$;

revoke all on function public.journal_exchange_rate_exact(uuid) from public,anon,authenticated;
grant execute on function public.journal_exchange_rate_exact(uuid) to authenticated;
