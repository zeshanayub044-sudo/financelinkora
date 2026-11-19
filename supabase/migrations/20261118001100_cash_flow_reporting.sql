-- Direct cash-flow reporting classifies the non-cash side of journal entries
-- that move cash or bank. Unclassified activity remains visible and is included
-- in the reconciliation total; nothing is silently forced into IFRS categories.
alter table public.accounts add column cash_flow_class text not null default 'unclassified'
  check (cash_flow_class in ('operating','investing','financing','unclassified'));

update public.accounts set cash_flow_class='operating'
where type in ('revenue','expense') or reporting_class in ('receivable','payable');

create or replace function private.default_account_cash_flow_class()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.cash_flow_class='unclassified' and (new.type in ('revenue','expense') or new.reporting_class in ('receivable','payable')) then
    new.cash_flow_class:='operating';
  end if;
  return new;
end;
$$;
revoke all on function private.default_account_cash_flow_class() from public,anon,authenticated;
create trigger default_account_cash_flow_class before insert on public.accounts
  for each row execute function private.default_account_cash_flow_class();

create index accounts_cash_flow_class_idx on public.accounts(org_id,cash_flow_class);

create or replace function public.cash_flow_statement_exact(p_org uuid,p_from date,p_to date)
returns table(section text,amount text)
language plpgsql stable security invoker set search_path = ''
as $$
begin
  if p_from is null or p_to is null or p_from>p_to then
    raise exception 'Choose a valid cash-flow reporting date range';
  end if;
  return query
  with cash_activity as (
    select a.cash_flow_class flow_class,coalesce(sum(l.base_credit-l.base_debit),0) amount
    from public.journal_entries e
    join public.journal_lines l on l.org_id=e.org_id and l.entry_id=e.id
    join public.accounts a on a.org_id=l.org_id and a.id=l.account_id
    where e.org_id=p_org and e.status in ('posted','reversed') and e.entry_date between p_from and p_to
      and (a.reporting_class is null or a.reporting_class not in ('cash','bank'))
      and exists (
        select 1 from public.journal_lines cl join public.accounts ca on ca.org_id=cl.org_id and ca.id=cl.account_id
        where cl.org_id=e.org_id and cl.entry_id=e.id and ca.reporting_class in ('cash','bank')
      )
    group by a.cash_flow_class
  ), classified as (
    select coalesce(sum(amount) filter(where flow_class='operating'),0) operating,
      coalesce(sum(amount) filter(where flow_class='investing'),0) investing,
      coalesce(sum(amount) filter(where flow_class='financing'),0) financing,
      coalesce(sum(amount) filter(where flow_class='unclassified'),0) unclassified
    from cash_activity
  ), cash_balances as (
    select coalesce(sum(l.base_debit-l.base_credit) filter(where e.entry_date<p_from),0) opening,
      coalesce(sum(l.base_debit-l.base_credit) filter(where e.entry_date<=p_to),0) closing,
      coalesce(sum(l.base_debit-l.base_credit) filter(where e.entry_date between p_from and p_to),0) movement
    from public.journal_entries e
    join public.journal_lines l on l.org_id=e.org_id and l.entry_id=e.id
    join public.accounts a on a.org_id=l.org_id and a.id=l.account_id
    where e.org_id=p_org and e.status in ('posted','reversed') and a.reporting_class in ('cash','bank')
      and e.entry_date<=p_to
  ), amounts as (
    select c.operating,c.investing,c.financing,c.unclassified,
      c.operating+c.investing+c.financing+c.unclassified net_change,
      b.opening,b.closing,b.movement
    from classified c cross join cash_balances b
  )
  select v.section,v.amount::text from amounts a
  cross join lateral (values
    ('operating',a.operating),('investing',a.investing),('financing',a.financing),
    ('unclassified',a.unclassified),('net_change',a.net_change),('opening_cash',a.opening),
    ('closing_cash',a.closing),('ledger_cash_movement',a.movement),
    ('reconciliation_difference',a.net_change-a.movement)
  ) v(section,amount)
  order by case v.section when 'operating' then 1 when 'investing' then 2 when 'financing' then 3
    when 'unclassified' then 4 when 'net_change' then 5 when 'opening_cash' then 6 when 'closing_cash' then 7
    when 'ledger_cash_movement' then 8 else 9 end;
end;
$$;

revoke all on function public.cash_flow_statement_exact(uuid,date,date) from public,anon,authenticated;
grant execute on function public.cash_flow_statement_exact(uuid,date,date) to authenticated;
