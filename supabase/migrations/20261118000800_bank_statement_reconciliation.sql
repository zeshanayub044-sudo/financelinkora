-- Bank statement activity is stored separately from the General Ledger.
-- Reconciliation only links imported rows to immutable posted ledger lines.
alter table public.journal_lines
  add constraint journal_lines_org_id_id_key unique (org_id,id);

create table public.bank_statement_imports (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  account_id uuid not null,
  file_name text not null check (length(trim(file_name)) between 1 and 255),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique (org_id,id),
  unique (org_id,id,account_id),
  foreign key (org_id,account_id) references public.accounts(org_id,id) on delete restrict
);

create table public.bank_statement_rows (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  import_id uuid not null,
  account_id uuid not null,
  row_number integer not null check (row_number between 1 and 5000),
  transaction_date date not null,
  description text not null check (length(trim(description)) between 1 and 500),
  reference text check (reference is null or length(reference)<=120),
  amount numeric(20,4) not null check (amount<>0 and amount::text not in ('NaN','Infinity','-Infinity')),
  matched_journal_line_id uuid,
  created_at timestamptz not null default now(),
  unique (org_id,id),
  unique (org_id,import_id,row_number),
  foreign key (org_id,import_id) references public.bank_statement_imports(org_id,id) on delete cascade,
  foreign key (org_id,import_id,account_id) references public.bank_statement_imports(org_id,id,account_id) on delete cascade,
  foreign key (org_id,account_id) references public.accounts(org_id,id) on delete restrict,
  foreign key (org_id,matched_journal_line_id) references public.journal_lines(org_id,id) on delete restrict
);

create index bank_statement_imports_account_created_idx
  on public.bank_statement_imports(org_id,account_id,created_at desc);
create index bank_statement_rows_import_date_idx
  on public.bank_statement_rows(org_id,import_id,transaction_date,row_number);
create unique index bank_statement_rows_one_match_idx
  on public.bank_statement_rows(org_id,matched_journal_line_id)
  where matched_journal_line_id is not null;

alter table public.bank_statement_imports enable row level security;
alter table public.bank_statement_rows enable row level security;
create policy bank_statement_imports_read on public.bank_statement_imports for select to authenticated
  using (private.has_role(org_id,array['owner','administrator','accountant','finance_manager','approver','auditor','viewer']::public.member_role[]));
create policy bank_statement_rows_read on public.bank_statement_rows for select to authenticated
  using (private.has_role(org_id,array['owner','administrator','accountant','finance_manager','approver','auditor','viewer']::public.member_role[]));
grant select on public.bank_statement_imports,public.bank_statement_rows to authenticated;
revoke all on public.bank_statement_imports,public.bank_statement_rows from anon;
revoke insert,update,delete on public.bank_statement_imports,public.bank_statement_rows from authenticated;

create trigger audit_bank_statement_imports after insert on public.bank_statement_imports
  for each row execute function private.audit_row();
create trigger audit_bank_statement_rows after insert or update on public.bank_statement_rows
  for each row execute function private.audit_row();

create or replace function public.import_bank_statement(
  p_org uuid,p_account uuid,p_file_name text,p_rows jsonb
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
  if p_rows is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>5000 then
    raise exception 'A statement must contain between 1 and 5000 rows';
  end if;
  if not exists(select 1 from public.accounts a where a.org_id=p_org and a.id=p_account
      and a.type='asset' and a.is_active and a.reporting_class in ('cash','bank')) then
    raise exception 'Choose an active cash or bank account in this organization';
  end if;

  insert into public.bank_statement_imports(org_id,account_id,file_name,created_by)
    values(p_org,p_account,trim(p_file_name),actor) returning id into new_import;

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
  select l.* into ledger_line
    from public.journal_lines l join public.journal_entries e on e.org_id=l.org_id and e.id=l.entry_id
    where l.id=p_journal_line and l.org_id=statement_row.org_id;
  if not found then raise exception 'Posted ledger line not found in this organization'; end if;
  select e.status into entry_status from public.journal_entries e
    where e.org_id=statement_row.org_id and e.id=ledger_line.entry_id;
  if ledger_line.account_id<>statement_row.account_id then raise exception 'Ledger line belongs to a different cash or bank account'; end if;
  if entry_status not in ('posted','reversed') then raise exception 'Only posted ledger activity can be reconciled'; end if;
  if ledger_line.debit-ledger_line.credit<>statement_row.amount then raise exception 'Statement amount does not equal the signed ledger amount'; end if;
  update public.bank_statement_rows set matched_journal_line_id=p_journal_line where id=p_row;
end;
$$;

create or replace view public.bank_reconciliation_candidates with (security_invoker=true) as
select l.id as journal_line_id,l.org_id,l.account_id,e.entry_no,e.entry_date,e.description,l.memo,
  (l.debit-l.credit)::text as amount,r.id as matched_statement_row_id
from public.journal_lines l
join public.journal_entries e on e.org_id=l.org_id and e.id=l.entry_id
left join public.bank_statement_rows r on r.org_id=l.org_id and r.matched_journal_line_id=l.id
where e.status in ('posted','reversed')
;

create or replace view public.bank_statement_rows_exact with (security_invoker=true) as
select id,org_id,import_id,account_id,row_number,transaction_date,description,reference,
  amount::text as amount,matched_journal_line_id,created_at
from public.bank_statement_rows;

revoke all on function public.import_bank_statement(uuid,uuid,text,jsonb) from public,anon,authenticated;
revoke all on function public.match_bank_statement_row(uuid,uuid) from public,anon,authenticated;
revoke all on public.bank_reconciliation_candidates,public.bank_statement_rows_exact from public,anon,authenticated;
grant execute on function public.import_bank_statement(uuid,uuid,text,jsonb) to authenticated;
grant execute on function public.match_bank_statement_row(uuid,uuid) to authenticated;
grant select on public.bank_reconciliation_candidates,public.bank_statement_rows_exact to authenticated;
