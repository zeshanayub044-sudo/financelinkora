-- Cash and bank deposits/withdrawals are paired ledger entries. The asset leg
-- must be explicitly classified cash/bank; the counter-account may be any
-- other account, so transfers cannot be mislabeled as income or expense.
alter table public.journal_entries drop constraint if exists journal_entries_entry_kind_check;
alter table public.journal_entries add constraint journal_entries_entry_kind_check check (entry_kind in (
  'general','opening_balance','income','expense','payment','bank_transfer','bank_deposit','bank_withdrawal',
  'reversal','closing','sales_invoice','purchase_bill','customer_payment','supplier_payment','depreciation','payroll'
));

create or replace function private.guard_bank_movement()
returns trigger language plpgsql set search_path = ''
as $$
declare line_count integer;cash_count integer;counter_count integer;
begin
  if new.entry_kind not in ('bank_deposit','bank_withdrawal') or new.status not in ('submitted','pending_approval','approved','posted') then return new; end if;
  select count(*) into line_count from public.journal_lines l where l.org_id=new.org_id and l.entry_id=new.id;
  if line_count<>2 then raise exception 'A bank deposit or withdrawal must contain exactly two journal lines'; end if;
  if new.entry_kind='bank_deposit' then
    select count(*) into cash_count from public.journal_lines l join public.accounts a on a.org_id=l.org_id and a.id=l.account_id
      where l.org_id=new.org_id and l.entry_id=new.id and l.debit>0 and l.credit=0 and a.type='asset' and a.is_active and a.reporting_class in ('cash','bank');
    select count(*) into counter_count from public.journal_lines l join public.accounts a on a.org_id=l.org_id and a.id=l.account_id
      where l.org_id=new.org_id and l.entry_id=new.id and l.debit=0 and l.credit>0 and not(a.type='asset' and a.reporting_class in ('cash','bank'));
  else
    select count(*) into cash_count from public.journal_lines l join public.accounts a on a.org_id=l.org_id and a.id=l.account_id
      where l.org_id=new.org_id and l.entry_id=new.id and l.debit=0 and l.credit>0 and a.type='asset' and a.is_active and a.reporting_class in ('cash','bank');
    select count(*) into counter_count from public.journal_lines l join public.accounts a on a.org_id=l.org_id and a.id=l.account_id
      where l.org_id=new.org_id and l.entry_id=new.id and l.debit>0 and l.credit=0 and not(a.type='asset' and a.reporting_class in ('cash','bank'));
  end if;
  if cash_count<>1 or counter_count<>1 then
    raise exception 'Bank movement requires one classified cash/bank leg and one non-cash/bank counter-account leg in the correct direction';
  end if;
  return new;
end;
$$;
revoke all on function private.guard_bank_movement() from public,anon,authenticated;
drop trigger if exists guard_bank_movement on public.journal_entries;
create trigger guard_bank_movement before update of status on public.journal_entries
  for each row execute function private.guard_bank_movement();
