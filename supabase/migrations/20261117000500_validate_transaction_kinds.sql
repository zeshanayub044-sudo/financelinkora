-- Constrain the entry kinds used by Income, Expenses, and Banking to the
-- accounting account classes they represent. All still use the same approval
-- and posting workflow as general journal entries.

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
  select j.org_id,j.entry_date,j.currency,j.exchange_rate,j.entry_kind,o.base_currency into e
    from public.journal_entries j
    join public.organizations o on o.id=j.org_id
    where j.id=p_entry;
  if not found then raise exception 'Journal entry not found'; end if;

  perform private.assert_open_period(e.org_id,e.entry_date);

  select count(*),coalesce(sum(l.debit),0),coalesce(sum(l.credit),0),
    coalesce(sum(l.base_debit),0),coalesce(sum(l.base_credit),0)
  into line_count,debit_total,credit_total,base_debit_total,base_credit_total
  from public.journal_lines l where l.entry_id=p_entry and l.org_id=e.org_id;

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
    where l.entry_id=p_entry and l.org_id=e.org_id and not a.is_active
  ) then raise exception 'Entry uses an inactive account'; end if;

  if e.entry_kind='income' and exists(
    select 1 from public.journal_lines l
    join public.accounts a on a.id=l.account_id and a.org_id=l.org_id
    where l.entry_id=p_entry and l.org_id=e.org_id
      and (a.type not in ('asset','revenue')
        or (l.debit>0 and a.type<>'asset')
        or (l.credit>0 and a.type<>'revenue'))
  ) then raise exception 'Income entries debit asset accounts and credit revenue accounts'; end if;
  if e.entry_kind='income' and (
    not exists(select 1 from public.journal_lines l join public.accounts a on a.id=l.account_id and a.org_id=l.org_id
      where l.entry_id=p_entry and l.org_id=e.org_id and l.debit>0 and a.type='asset')
    or not exists(select 1 from public.journal_lines l join public.accounts a on a.id=l.account_id and a.org_id=l.org_id
      where l.entry_id=p_entry and l.org_id=e.org_id and l.credit>0 and a.type='revenue')
  ) then raise exception 'Income entries need an asset debit and revenue credit'; end if;

  if e.entry_kind='expense' and exists(
    select 1 from public.journal_lines l
    join public.accounts a on a.id=l.account_id and a.org_id=l.org_id
    where l.entry_id=p_entry and l.org_id=e.org_id
      and (a.type not in ('asset','expense')
        or (l.debit>0 and a.type<>'expense')
        or (l.credit>0 and a.type<>'asset'))
  ) then raise exception 'Expense entries debit expense accounts and credit asset accounts'; end if;
  if e.entry_kind='expense' and (
    not exists(select 1 from public.journal_lines l join public.accounts a on a.id=l.account_id and a.org_id=l.org_id
      where l.entry_id=p_entry and l.org_id=e.org_id and l.debit>0 and a.type='expense')
    or not exists(select 1 from public.journal_lines l join public.accounts a on a.id=l.account_id and a.org_id=l.org_id
      where l.entry_id=p_entry and l.org_id=e.org_id and l.credit>0 and a.type='asset')
  ) then raise exception 'Expense entries need an expense debit and asset credit'; end if;

  if e.entry_kind='bank_transfer' and exists(
    select 1 from public.journal_lines l
    join public.accounts a on a.id=l.account_id and a.org_id=l.org_id
    where l.entry_id=p_entry and l.org_id=e.org_id and a.type<>'asset'
  ) then raise exception 'Internal transfers may only use asset accounts'; end if;
  if e.entry_kind='bank_transfer' and not exists(
    select 1 from public.journal_lines d
    join public.accounts da on da.id=d.account_id and da.org_id=d.org_id
    join public.journal_lines c on c.entry_id=d.entry_id and c.org_id=d.org_id and c.credit>0
    join public.accounts ca on ca.id=c.account_id and ca.org_id=c.org_id
    where d.entry_id=p_entry and d.org_id=e.org_id and d.debit>0
      and da.type='asset' and ca.type='asset' and da.id<>ca.id
  ) then raise exception 'A bank transfer must move value between two different asset accounts'; end if;
end;
$$;

revoke all on function private.validate_journal_entry(uuid) from public,anon,authenticated;
