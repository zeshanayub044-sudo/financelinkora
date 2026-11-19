-- Explicit account roles make liquidity and working-capital totals auditable.
alter table public.accounts add column reporting_class text;
alter table public.accounts add constraint accounts_reporting_class_check check (
  reporting_class is null
  or (reporting_class in ('cash','bank','receivable') and type='asset')
  or (reporting_class='payable' and type='liability')
);
-- Map only the original starter chart codes. Custom accounts remain unclassified
-- until an authorized user explicitly assigns a reporting role.
update public.accounts set reporting_class=case code
  when '1000' then 'cash'
  when '1100' then 'bank'
  when '1200' then 'receivable'
  when '2000' then 'payable'
end
where (code='1000' and type='asset')
   or (code='1100' and type='asset')
   or (code='1200' and type='asset')
   or (code='2000' and type='liability');

create or replace function public.financial_summary(p_org uuid,p_from date,p_to date,p_as_of date)
returns table(income numeric,expenses numeric,profit numeric,assets numeric,liabilities numeric,equity numeric,
  cash_balance numeric,bank_balance numeric,accounts_receivable numeric,accounts_payable numeric)
language sql stable security invoker set search_path = ''
as $$
  with period_pl as (
    select coalesce(sum(amount) filter(where type='revenue'),0) income,
      coalesce(sum(amount) filter(where type='expense'),0) expenses
    from public.profit_and_loss(p_org,p_from,p_to)
  ),
  lifetime_pl as (
    select coalesce(sum(amount) filter(where type='revenue'),0) income,
      coalesce(sum(amount) filter(where type='expense'),0) expenses
    from public.profit_and_loss(p_org,date '0001-01-01',p_as_of)
  ),
  balances as (
    select t.code,t.name,t.type,a.reporting_class,
      case when t.type in ('asset','expense') then t.debit-t.credit else t.credit-t.debit end value
    from public.trial_balance_as_of(p_org,p_as_of) t
    join public.accounts a on a.org_id=p_org and a.code=t.code
  ),
  sums as (
    select coalesce(sum(value) filter(where type='asset'),0) assets,
      coalesce(sum(value) filter(where type='liability'),0) liabilities,
      coalesce(sum(value) filter(where type='equity'),0) equity,
      coalesce(sum(value) filter(where reporting_class='cash'),0) cash_balance,
      coalesce(sum(value) filter(where reporting_class='bank'),0) bank_balance,
      coalesce(sum(value) filter(where reporting_class='receivable'),0) accounts_receivable,
      coalesce(sum(value) filter(where reporting_class='payable'),0) accounts_payable
    from balances
  )
  select p.income,p.expenses,p.income-p.expenses,s.assets,s.liabilities,s.equity+lp.income-lp.expenses,
    s.cash_balance,s.bank_balance,s.accounts_receivable,s.accounts_payable
  from period_pl p cross join sums s cross join lifetime_pl lp;
$$;

revoke all on function public.financial_summary(uuid,date,date,date) from public,anon,authenticated;
grant execute on function public.financial_summary(uuid,date,date,date) to authenticated;

create or replace function public.financial_summary_exact(p_org uuid,p_from date,p_to date,p_as_of date)
returns table(income text,expenses text,profit text,assets text,liabilities text,equity text,
  cash_balance text,bank_balance text,accounts_receivable text,accounts_payable text)
language sql stable security invoker set search_path = ''
as $$
  select r.income::text,r.expenses::text,r.profit::text,r.assets::text,r.liabilities::text,r.equity::text,
    r.cash_balance::text,r.bank_balance::text,r.accounts_receivable::text,r.accounts_payable::text
  from public.financial_summary(p_org,p_from,p_to,p_as_of) r;
$$;
revoke all on function public.financial_summary_exact(uuid,date,date,date) from public,anon,authenticated;
grant execute on function public.financial_summary_exact(uuid,date,date,date) to authenticated;
