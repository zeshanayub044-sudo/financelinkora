-- Capture statement periods and balances for full bank-vs-ledger reconciliation.
-- Historical imports remain readable but are reported as missing balances.
alter table public.bank_statement_imports
  add column statement_start_date date,
  add column statement_end_date date,
  add column opening_balance numeric(20,4),
  add column closing_balance numeric(20,4),
  add constraint bank_statement_imports_period_check
    check (statement_start_date is null or statement_end_date is null or statement_start_date<=statement_end_date),
  add constraint bank_statement_imports_opening_finite_check
    check (opening_balance is null or (opening_balance::text not in ('NaN','Infinity','-Infinity') and opening_balance=round(opening_balance,4))),
  add constraint bank_statement_imports_closing_finite_check
    check (closing_balance is null or (closing_balance::text not in ('NaN','Infinity','-Infinity') and closing_balance=round(closing_balance,4)));

revoke all on function public.import_bank_statement(uuid,uuid,text,jsonb) from public,anon,authenticated;
drop function public.import_bank_statement(uuid,uuid,text,jsonb);

create function public.import_bank_statement(
  p_org uuid,p_account uuid,p_file_name text,p_start_date date,p_end_date date,
  p_opening_balance numeric,p_closing_balance numeric,p_rows jsonb
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid:=auth.uid();
  new_import uuid;
  item jsonb;
  row_index bigint;
  row_date date;
  row_amount numeric;
  row_description text;
  row_reference text;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then
    raise exception 'Not authorized to import bank statements';
  end if;
  if nullif(trim(p_file_name),'') is null or length(p_file_name)>255 then raise exception 'Invalid statement file name'; end if;
  if p_start_date is null or p_end_date is null or p_start_date>p_end_date then raise exception 'Invalid bank statement date range'; end if;
  if p_opening_balance is null or p_closing_balance is null
     or p_opening_balance::text in ('NaN','Infinity','-Infinity')
     or p_closing_balance::text in ('NaN','Infinity','-Infinity')
     or p_opening_balance<>round(p_opening_balance,4) or p_closing_balance<>round(p_closing_balance,4) then
    raise exception 'Statement balances must be finite values with at most four decimal places';
  end if;
  if p_rows is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>5000 then
    raise exception 'A statement must contain between 1 and 5000 rows';
  end if;
  if not exists(select 1 from public.accounts a where a.org_id=p_org and a.id=p_account
      and a.type='asset' and a.is_active and a.reporting_class in ('cash','bank')) then
    raise exception 'Choose an active cash or bank account in this organization';
  end if;

  insert into public.bank_statement_imports(org_id,account_id,file_name,created_by,statement_start_date,statement_end_date,opening_balance,closing_balance)
    values(p_org,p_account,trim(p_file_name),actor,p_start_date,p_end_date,p_opening_balance,p_closing_balance) returning id into new_import;

  for item,row_index in select value,ordinality from jsonb_array_elements(p_rows) with ordinality as source(value,ordinality) loop
    if jsonb_typeof(item)<>'object' then raise exception 'Statement row % must be an object',row_index; end if;
    if coalesce(item->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
       or coalesce(item->>'amount','') !~ '^-?(0|[1-9][0-9]{0,15})(\.[0-9]{1,4})?$' then
      raise exception 'Statement row % has an invalid date or amount format',row_index;
    end if;
    begin
      row_date:=(item->>'date')::date;
      row_amount:=(item->>'amount')::numeric;
    exception when others then raise exception 'Statement row % has an invalid date or amount',row_index; end;
    row_description:=nullif(trim(item->>'description'),'');
    row_reference:=nullif(trim(item->>'reference'),'');
    if row_date<p_start_date or row_date>p_end_date then raise exception 'Statement row % is outside the statement period',row_index; end if;
    if row_date is null or row_amount is null or row_amount=0
       or row_amount::text in ('NaN','Infinity','-Infinity') or row_amount<>round(row_amount,4) then
      raise exception 'Statement row % requires a non-zero finite amount with at most four decimal places',row_index;
    end if;
    if row_description is null or length(row_description)>500 or length(row_reference)>120 then
      raise exception 'Statement row % has an invalid description or reference',row_index;
    end if;
    insert into public.bank_statement_rows(org_id,import_id,account_id,row_number,transaction_date,description,reference,amount)
      values(p_org,new_import,p_account,row_index::integer,row_date,row_description,row_reference,row_amount);
  end loop;
  return new_import;
end;
$$;

create or replace function public.match_bank_statement_row(p_row uuid,p_journal_line uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid:=auth.uid();
  statement_row public.bank_statement_rows%rowtype;
  ledger_line public.journal_lines%rowtype;
  entry_status public.entry_status;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  select * into statement_row from public.bank_statement_rows where id=p_row for update;
  if not found then raise exception 'Statement row not found'; end if;
  if not private.has_role(statement_row.org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then
    raise exception 'Not authorized to reconcile bank statements';
  end if;
  if p_journal_line is null then
    update public.bank_statement_rows set matched_journal_line_id=null where id=p_row;
    return;
  end if;
  select l.* into ledger_line from public.journal_lines l
    join public.journal_entries e on e.org_id=l.org_id and e.id=l.entry_id
    where l.id=p_journal_line and l.org_id=statement_row.org_id;
  if not found then raise exception 'Posted ledger line not found in this organization'; end if;
  select e.status into entry_status from public.journal_entries e
    where e.org_id=statement_row.org_id and e.id=ledger_line.entry_id;
  if ledger_line.account_id<>statement_row.account_id then raise exception 'Ledger line belongs to a different cash or bank account'; end if;
  if entry_status not in ('posted','reversed') then raise exception 'Only posted ledger activity can be reconciled'; end if;
  if ledger_line.base_debit-ledger_line.base_credit<>statement_row.amount then raise exception 'Statement amount does not equal the signed functional-currency ledger amount'; end if;
  update public.bank_statement_rows set matched_journal_line_id=p_journal_line where id=p_row;
end;
$$;

create or replace view public.bank_reconciliation_candidates with (security_invoker=true) as
select l.id as journal_line_id,l.org_id,l.account_id,e.entry_no,e.entry_date,e.description,l.memo,
  (l.base_debit-l.base_credit)::text as amount,r.id as matched_statement_row_id
from public.journal_lines l
join public.journal_entries e on e.org_id=l.org_id and e.id=l.entry_id
left join public.bank_statement_rows r on r.org_id=l.org_id and r.matched_journal_line_id=l.id
where e.status in ('posted','reversed');

create or replace function public.bank_reconciliation_report_exact(p_import uuid)
returns table(
  import_id uuid,account_id uuid,account_name text,base_currency text,
  statement_start_date date,statement_end_date date,opening_balance text,closing_balance text,
  statement_calculated_closing text,ledger_opening_balance text,ledger_closing_balance text,
  opening_difference text,closing_difference text,statement_activity_difference text,
  unmatched_statement_activity text,unmatched_ledger_activity text,unmatched_activity_difference text,
  is_reconciled boolean
)
language sql stable security invoker set search_path = ''
as $$
  with target as (
    select i.id,i.org_id,i.account_id,a.name account_name,o.base_currency::text base_currency,
      i.statement_start_date,i.statement_end_date,i.opening_balance,i.closing_balance
    from public.bank_statement_imports i
    join public.accounts a on a.org_id=i.org_id and a.id=i.account_id
    join public.organizations o on o.id=i.org_id
    where i.id=p_import and i.statement_start_date is not null and i.statement_end_date is not null
      and i.opening_balance is not null and i.closing_balance is not null
  ),
  statement_values as (
    select t.id,coalesce(sum(r.amount),0) statement_activity,
      coalesce(sum(r.amount) filter(where r.matched_journal_line_id is null),0) unmatched_statement
    from target t left join public.bank_statement_rows r on r.org_id=t.org_id and r.import_id=t.id
    group by t.id
  ),
  ledger_values as (
    select t.id,
      coalesce(sum(l.base_debit-l.base_credit) filter(where e.entry_date<t.statement_start_date),0) ledger_opening,
      coalesce(sum(l.base_debit-l.base_credit) filter(where e.entry_date<=t.statement_end_date),0) ledger_closing,
      coalesce(sum(l.base_debit-l.base_credit) filter(where e.entry_date between t.statement_start_date and t.statement_end_date and r.id is null),0) unmatched_ledger
    from target t
    left join public.journal_lines l on l.org_id=t.org_id and l.account_id=t.account_id
    left join public.journal_entries e on e.org_id=l.org_id and e.id=l.entry_id and e.status in ('posted','reversed')
    left join public.bank_statement_rows r on r.org_id=l.org_id and r.matched_journal_line_id=l.id
    group by t.id
  )
  select t.id,t.account_id,t.account_name,t.base_currency,t.statement_start_date,t.statement_end_date,
    t.opening_balance::text,t.closing_balance::text,(t.opening_balance+s.statement_activity)::text,
    lv.ledger_opening::text,lv.ledger_closing::text,(t.opening_balance-lv.ledger_opening)::text,
    (t.closing_balance-lv.ledger_closing)::text,(t.closing_balance-t.opening_balance-s.statement_activity)::text,
    s.unmatched_statement::text,lv.unmatched_ledger::text,(s.unmatched_statement-lv.unmatched_ledger)::text,
    (t.opening_balance=lv.ledger_opening and t.closing_balance=lv.ledger_closing
      and t.closing_balance=t.opening_balance+s.statement_activity)
  from target t join statement_values s on s.id=t.id join ledger_values lv on lv.id=t.id;
$$;

revoke all on function public.import_bank_statement(uuid,uuid,text,date,date,numeric,numeric,jsonb) from public,anon,authenticated;
revoke all on function public.bank_reconciliation_report_exact(uuid) from public,anon,authenticated;
grant execute on function public.import_bank_statement(uuid,uuid,text,date,date,numeric,numeric,jsonb) to authenticated;
grant execute on function public.bank_reconciliation_report_exact(uuid) to authenticated;
