-- Preserve PostgreSQL NUMERIC values as decimal text across PostgREST's JSON
-- boundary. Existing numeric RPCs remain available for compatibility.

-- PostgreSQL NUMERIC supports special values such as NaN. NaN compares equal
-- to itself and can pass ordinary non-negative/balance checks, so reject all
-- non-finite line and exchange-rate values at the storage boundary.
alter table public.journal_lines
  add constraint journal_lines_debit_finite_check
    check (debit::text not in ('NaN','Infinity','-Infinity')) not valid,
  add constraint journal_lines_credit_finite_check
    check (credit::text not in ('NaN','Infinity','-Infinity')) not valid,
  add constraint journal_lines_exchange_rate_finite_check
    check (exchange_rate::text not in ('NaN','Infinity','-Infinity')) not valid,
  add constraint journal_lines_base_debit_finite_check
    check (base_debit::text not in ('NaN','Infinity','-Infinity')) not valid,
  add constraint journal_lines_base_credit_finite_check
    check (base_credit::text not in ('NaN','Infinity','-Infinity')) not valid;
alter table public.journal_lines
  validate constraint journal_lines_debit_finite_check,
  validate constraint journal_lines_credit_finite_check,
  validate constraint journal_lines_exchange_rate_finite_check,
  validate constraint journal_lines_base_debit_finite_check,
  validate constraint journal_lines_base_credit_finite_check;

alter table public.journal_entries
  add constraint journal_entries_exchange_rate_finite_check
    check (exchange_rate::text not in ('NaN','Infinity','-Infinity')) not valid;
alter table public.journal_entries validate constraint journal_entries_exchange_rate_finite_check;

create or replace function public.trial_balance_exact(p_org uuid,p_from date,p_to date)
returns table(code text,name text,type public.account_type,debit text,credit text)
language sql stable security invoker set search_path = ''
as $$
  select r.code,r.name,r.type,r.debit::text,r.credit::text
  from public.trial_balance(p_org,p_from,p_to) r;
$$;

create or replace function public.trial_balance_as_of_exact(p_org uuid,p_as_of date)
returns table(code text,name text,type public.account_type,debit text,credit text)
language sql stable security invoker set search_path = ''
as $$
  select r.code,r.name,r.type,r.debit::text,r.credit::text
  from public.trial_balance_as_of(p_org,p_as_of) r;
$$;

create or replace function public.profit_and_loss_exact(p_org uuid,p_from date,p_to date)
returns table(code text,name text,type public.account_type,amount text)
language sql stable security invoker set search_path = ''
as $$
  select r.code,r.name,r.type,r.amount::text
  from public.profit_and_loss(p_org,p_from,p_to) r;
$$;

create or replace function public.balance_sheet_exact(p_org uuid,p_as_of date)
returns table(section text,code text,name text,balance text)
language sql stable security invoker set search_path = ''
as $$
  select r.section,r.code,r.name,r.balance::text
  from public.balance_sheet(p_org,p_as_of) r;
$$;

create or replace function public.financial_summary_exact(p_org uuid,p_from date,p_to date,p_as_of date)
returns table(income text,expenses text,profit text,assets text,liabilities text,equity text,
  cash_balance text,bank_balance text,accounts_receivable text,accounts_payable text)
language sql stable security invoker set search_path = ''
as $$
  select r.income::text,r.expenses::text,r.profit::text,r.assets::text,r.liabilities::text,r.equity::text,
    r.cash_balance::text,r.bank_balance::text,r.accounts_receivable::text,r.accounts_payable::text
  from public.financial_summary(p_org,p_from,p_to,p_as_of) r;
$$;

create or replace function public.monthly_financial_activity_exact(p_org uuid,p_from date)
returns table(month_start date,revenue text,expenses text)
language sql stable security invoker set search_path = ''
as $$
  select r.month_start,r.revenue::text,r.expenses::text
  from public.monthly_financial_activity(p_org,p_from) r;
$$;

create or replace function public.journal_entry_lines_exact(p_entry uuid)
returns table(id uuid,account_id uuid,debit text,credit text,memo text)
language sql stable security invoker set search_path = ''
as $$
  select l.id,l.account_id,l.debit::text,l.credit::text,l.memo
  from public.journal_lines l where l.entry_id=p_entry order by l.id;
$$;

create or replace view public.ledger_exact with (security_invoker=true) as
select l.org_id,l.account_id,l.code,l.account_name,l.entry_id,l.entry_no,l.entry_date,l.description,l.memo,
  l.debit::text as debit,l.credit::text as credit,l.running_balance::text as running_balance,
  l.currency,l.exchange_rate,l.transaction_debit::text as transaction_debit,
  l.transaction_credit::text as transaction_credit
from public.ledger l;

revoke all on function public.trial_balance_exact(uuid,date,date) from public,anon,authenticated;
revoke all on function public.trial_balance_as_of_exact(uuid,date) from public,anon,authenticated;
revoke all on function public.profit_and_loss_exact(uuid,date,date) from public,anon,authenticated;
revoke all on function public.balance_sheet_exact(uuid,date) from public,anon,authenticated;
revoke all on function public.financial_summary_exact(uuid,date,date,date) from public,anon,authenticated;
revoke all on function public.monthly_financial_activity_exact(uuid,date) from public,anon,authenticated;
revoke all on function public.journal_entry_lines_exact(uuid) from public,anon,authenticated;
revoke all on public.ledger_exact from public,anon,authenticated;
grant execute on function public.trial_balance_exact(uuid,date,date) to authenticated;
grant execute on function public.trial_balance_as_of_exact(uuid,date) to authenticated;
grant execute on function public.profit_and_loss_exact(uuid,date,date) to authenticated;
grant execute on function public.balance_sheet_exact(uuid,date) to authenticated;
grant execute on function public.financial_summary_exact(uuid,date,date,date) to authenticated;
grant execute on function public.monthly_financial_activity_exact(uuid,date) to authenticated;
grant execute on function public.journal_entry_lines_exact(uuid) to authenticated;
grant select on public.ledger_exact to authenticated;
