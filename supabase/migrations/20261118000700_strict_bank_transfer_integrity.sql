-- An internal transfer is one movement between exactly two distinct asset
-- accounts. Fees or income/expense legs belong in separate journal entries.
-- Enforce the shape at every workflow transition, including direct SQL updates.
create or replace function private.guard_bank_transfer_shape()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  line_count bigint;
  debit_count bigint;
  credit_count bigint;
  account_count bigint;
begin
  if new.entry_kind <> 'bank_transfer'
     or new.status not in ('submitted','pending_approval','approved','posted')
     or new.status is not distinct from old.status then
    return new;
  end if;

  select count(*),count(*) filter (where l.debit>0),count(*) filter (where l.credit>0),count(distinct l.account_id)
    into line_count,debit_count,credit_count,account_count
    from public.journal_lines l
    where l.entry_id=new.id and l.org_id=new.org_id;

  if line_count<>2 or debit_count<>1 or credit_count<>1 then
    raise exception 'A bank transfer must contain exactly two lines, one debit and one credit';
  end if;
  if account_count<>2 then
    raise exception 'A bank transfer must use two different asset accounts';
  end if;
  if exists(
    select 1 from public.journal_lines l
    join public.accounts a on a.id=l.account_id and a.org_id=l.org_id
    where l.entry_id=new.id and l.org_id=new.org_id
      and (a.reporting_class is null or a.reporting_class not in ('cash','bank'))
  ) then
    raise exception 'Internal transfers may only use cash or bank accounts';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_bank_transfer_shape() from public,anon,authenticated;
drop trigger if exists guard_bank_transfer_shape on public.journal_entries;
create trigger guard_bank_transfer_shape
  before update of status on public.journal_entries
  for each row execute function private.guard_bank_transfer_shape();
