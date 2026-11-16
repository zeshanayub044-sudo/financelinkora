-- Prevent per-line NUMERIC rounding from making the functional-currency ledger
-- unbalanced when a foreign-currency entry is submitted, approved, or posted.
-- The current UI uses the organization currency; this also protects future
-- manual-rate entries until a dedicated FX rounding adjustment workflow exists.

create or replace function private.validate_journal_entry(p_entry uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  e record;
  line_count bigint;
  debit_total numeric(30,4);
  credit_total numeric(30,4);
  base_debit_total numeric(38,4);
  base_credit_total numeric(38,4);
begin
  select j.org_id,j.entry_date,j.currency,j.exchange_rate,o.base_currency into e
    from public.journal_entries j
    join public.organizations o on o.id=j.org_id
    where j.id=p_entry;
  if not found then raise exception 'Journal entry not found'; end if;

  perform private.assert_open_period(e.org_id,e.entry_date);

  select count(*),
    coalesce(sum(l.debit),0),
    coalesce(sum(l.credit),0),
    coalesce(sum(l.base_debit),0),
    coalesce(sum(l.base_credit),0)
  into line_count,debit_total,credit_total,base_debit_total,base_credit_total
  from public.journal_lines l
  where l.entry_id=p_entry;

  if line_count<2 then raise exception 'A journal entry needs at least two lines'; end if;
  if debit_total<>credit_total then
    raise exception 'Unbalanced entry: debit % does not equal credit %',debit_total,credit_total;
  end if;
  if base_debit_total<>base_credit_total then
    raise exception 'Functional-currency rounding imbalance: debit % does not equal credit %',base_debit_total,base_credit_total;
  end if;
  if e.currency=e.base_currency and e.exchange_rate<>1 then
    raise exception 'Base-currency entries must use an exchange rate of 1';
  end if;
  if exists(
    select 1 from public.journal_lines l
    join public.accounts a on a.id=l.account_id and a.org_id=l.org_id
    where l.entry_id=p_entry and not a.is_active
  ) then
    raise exception 'Entry uses an inactive account';
  end if;
end;
$$;

revoke all on function private.validate_journal_entry(uuid) from public,anon,authenticated;

