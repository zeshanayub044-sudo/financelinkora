-- Additive hardening for the existing Linkora foundation.
-- This migration assumes 20261117000100_extend_workflow_roles.sql has committed first.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create or replace function private.is_member(p_org uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists(select 1 from public.organization_members m where m.org_id=p_org and m.user_id=auth.uid()); $$;
create or replace function private.has_role(p_org uuid, p_roles public.member_role[])
returns boolean language sql stable security definer set search_path = ''
as $$ select exists(select 1 from public.organization_members m where m.org_id=p_org and m.user_id=auth.uid() and m.role=any(p_roles)); $$;
grant execute on function private.is_member(uuid) to authenticated;
grant execute on function private.has_role(uuid, public.member_role[]) to authenticated;

create or replace function public.is_member(p_org uuid)
returns boolean language sql stable security invoker set search_path = ''
as $$ select private.is_member(p_org); $$;
create or replace function public.has_role(p_org uuid, p_roles public.member_role[])
returns boolean language sql stable security invoker set search_path = ''
as $$ select private.has_role(p_org,p_roles); $$;

alter table public.journal_entries
  add column if not exists submitted_at timestamptz,
  add column if not exists rejected_at timestamptz,
  add column if not exists rejected_by uuid references auth.users(id),
  add column if not exists rejection_reason text,
  add column if not exists reversal_reason text,
  add column if not exists entry_kind text not null default 'general'
    check (entry_kind in ('general','opening_balance','income','expense','payment','bank_transfer','reversal','closing'));
alter table public.journal_lines
  add column if not exists exchange_rate numeric(18,8) not null default 1 check (exchange_rate > 0),
  add column if not exists base_debit numeric(20,4) generated always as (round(debit * exchange_rate, 4)) stored,
  add column if not exists base_credit numeric(20,4) generated always as (round(credit * exchange_rate, 4)) stored;

alter table public.accounts add constraint accounts_org_id_id_key unique (org_id,id);
alter table public.journal_entries add constraint journal_entries_org_id_id_key unique (org_id,id);
alter table public.journal_entries
  drop constraint if exists journal_entries_reverses_id_fkey,
  add constraint journal_entries_reverses_org_fk foreign key (org_id,reverses_id)
    references public.journal_entries(org_id,id) on delete restrict,
  add constraint journal_entries_reversal_kind_check
    check ((entry_kind='reversal') = (reverses_id is not null));
alter table public.accounts
  drop constraint if exists accounts_parent_id_fkey,
  add constraint accounts_parent_org_fk foreign key (org_id,parent_id)
    references public.accounts(org_id,id) on delete restrict;
alter table public.journal_lines
  drop constraint if exists journal_lines_entry_id_fkey,
  drop constraint if exists journal_lines_account_id_fkey,
  add constraint journal_lines_entry_org_fk foreign key (org_id,entry_id)
    references public.journal_entries(org_id,id) on delete cascade,
  add constraint journal_lines_account_org_fk foreign key (org_id,account_id)
    references public.accounts(org_id,id) on delete restrict;

create unique index if not exists journal_entries_one_reversal_per_source
  on public.journal_entries(org_id,reverses_id) where reverses_id is not null;
create index if not exists journal_entries_org_status_date_idx
  on public.journal_entries(org_id,status,entry_date desc);
create index if not exists journal_lines_entry_account_idx
  on public.journal_lines(entry_id,account_id);
create index if not exists accounting_periods_org_dates_idx
  on public.accounting_periods(org_id,start_date,end_date);

create or replace function private.audit_row()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  old_doc jsonb;
  new_doc jsonb;
  row_doc jsonb;
  target_org uuid;
  target_entity uuid;
  event_action text;
begin
  if tg_op <> 'INSERT' then old_doc := to_jsonb(old); end if;
  if tg_op <> 'DELETE' then new_doc := to_jsonb(new); end if;
  row_doc := coalesce(new_doc,old_doc);
  if tg_table_name='organizations' then target_org := (row_doc->>'id')::uuid;
  else target_org := nullif(row_doc->>'org_id','')::uuid; end if;
  if tg_table_name='organizations' and tg_op='UPDATE'
     and (old_doc - 'journal_seq') = (new_doc - 'journal_seq') then
    return new;
  end if;
  target_entity := coalesce(nullif(row_doc->>'id','')::uuid,
                            nullif(row_doc->>'user_id','')::uuid,
                            nullif(row_doc->>'entry_id','')::uuid);
  event_action := lower(tg_op);
  if tg_table_name='journal_entries' and tg_op='UPDATE'
     and old_doc->>'status' is distinct from new_doc->>'status' then
    event_action := case
      when new_doc->>'status'='submitted' then 'journal_submitted'
      when new_doc->>'status'='pending_approval' then 'journal_queued'
      when new_doc->>'status'='approved' then 'journal_approved'
      when new_doc->>'status'='posted' then 'journal_posted'
      when new_doc->>'status'='reversed' then 'journal_reversed'
      when new_doc->>'status'='draft' and nullif(new_doc->>'rejection_reason','') is not null then 'journal_rejected'
      else 'journal_status_changed'
    end;
  end if;
  insert into public.audit_logs(org_id,user_id,action,entity_type,entity_id,old_values,new_values)
    values(target_org,auth.uid(),event_action,tg_table_name,target_entity,old_doc,new_doc);
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function private.audit_row() from public, anon, authenticated;

drop trigger if exists audit_accounts on public.accounts;
drop trigger if exists audit_entries on public.journal_entries;
drop trigger if exists audit_orgs on public.organizations;
drop trigger if exists audit_periods on public.accounting_periods;
drop trigger if exists audit_members on public.organization_members;
drop trigger if exists audit_lines on public.journal_lines;
create trigger audit_accounts after insert or update or delete on public.accounts for each row execute function private.audit_row();
create trigger audit_entries after insert or update or delete on public.journal_entries for each row execute function private.audit_row();
create trigger audit_orgs after insert or update or delete on public.organizations for each row execute function private.audit_row();
create trigger audit_periods after insert or update or delete on public.accounting_periods for each row execute function private.audit_row();
create trigger audit_members after insert or update or delete on public.organization_members for each row execute function private.audit_row();
create trigger audit_lines after insert or update or delete on public.journal_lines for each row execute function private.audit_row();

create or replace function public.trg_entry_number()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare next_number bigint;
begin
  update public.organizations set journal_seq=journal_seq+1 where id=new.org_id
    returning journal_seq into next_number;
  if next_number is null then raise exception 'Organization not found'; end if;
  new.entry_no := 'JE-'||lpad(next_number::text,6,'0');
  return new;
end;
$$;

create or replace function public.trg_entry_guard()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if tg_op='DELETE' then
    if old.status<>'draft' then raise exception 'Only draft entries may be deleted'; end if;
    if old.created_by is distinct from auth.uid() and current_user<>'postgres' then
      raise exception 'Only the creator may delete a draft entry';
    end if;
    return old;
  end if;
  if tg_op='INSERT' then
    if new.status<>'draft' or new.approved_by is not null or new.posted_at is not null then
      raise exception 'Journal entries must be created as drafts';
    end if;
    if new.submitted_at is not null or new.rejected_at is not null or new.rejected_by is not null
       or new.rejection_reason is not null or new.reversal_reason is not null then
      raise exception 'Workflow metadata is database-managed';
    end if;
    if current_user<>'postgres' and (new.entry_kind='reversal' or new.reverses_id is not null) then
      raise exception 'Reversals must be created through reverse_journal_entry';
    end if;
    if new.created_by is distinct from auth.uid() and current_user<>'postgres' then
      raise exception 'The creator must be the authenticated user';
    end if;
    return new;
  end if;
  if current_user<>'postgres' and old.status<>'draft' then raise exception 'Only draft entries may be edited'; end if;
  if new.id is distinct from old.id or new.org_id is distinct from old.org_id
     or new.created_by is distinct from old.created_by or new.entry_no is distinct from old.entry_no
     or new.entry_kind is distinct from old.entry_kind or new.reverses_id is distinct from old.reverses_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Journal entry identity fields are immutable';
  end if;
  if current_user<>'postgres' and (
       new.status is distinct from old.status or new.approved_by is distinct from old.approved_by
       or new.posted_at is distinct from old.posted_at or new.submitted_at is distinct from old.submitted_at
       or new.rejected_at is distinct from old.rejected_at or new.rejected_by is distinct from old.rejected_by
       or new.rejection_reason is distinct from old.rejection_reason or new.reversal_reason is distinct from old.reversal_reason) then
    raise exception 'Workflow fields may only be changed by accounting functions';
  end if;
  return new;
end;
$$;

create or replace function public.trg_line_guard()
returns trigger language plpgsql set search_path = ''
as $$
declare
  entry_state public.entry_status;
  entry_org uuid;
  entry_rate numeric(18,8);
  target_entry uuid;
begin
  if tg_op='DELETE' then target_entry:=old.entry_id; else target_entry:=new.entry_id; end if;
  if tg_op='UPDATE' and (new.entry_id is distinct from old.entry_id or new.org_id is distinct from old.org_id) then
    raise exception 'A journal line cannot be moved between entries or organizations';
  end if;
  select e.status,e.org_id,e.exchange_rate into entry_state,entry_org,entry_rate
    from public.journal_entries e where e.id=target_entry for update;
  if not found then raise exception 'Journal entry not found'; end if;
  if entry_state<>'draft' then raise exception 'Lines can only be changed on draft entries'; end if;
  if tg_op<>'DELETE' then
    if new.org_id<>entry_org then raise exception 'Line organization must match entry organization'; end if;
    if not exists(select 1 from public.accounts a where a.id=new.account_id and a.org_id=entry_org) then
      raise exception 'Account does not belong to this organization';
    end if;
    if not exists(select 1 from public.accounts a where a.id=new.account_id and a.is_active) then
      raise exception 'Inactive accounts cannot receive postings';
    end if;
    new.exchange_rate:=entry_rate;
    return new;
  end if;
  return old;
end;
$$;

create or replace function private.check_period_range()
returns trigger language plpgsql set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.org_id::text,0));
  if exists(
    select 1 from public.accounting_periods p where p.org_id=new.org_id and p.id is distinct from new.id
      and daterange(p.start_date,p.end_date,'[]') && daterange(new.start_date,new.end_date,'[]')
  ) then raise exception 'Accounting periods cannot overlap'; end if;
  if tg_op='UPDATE' and (new.start_date,new.end_date) is distinct from (old.start_date,old.end_date)
     and exists(select 1 from public.journal_entries e where e.org_id=old.org_id
       and e.status in ('posted','reversed') and e.entry_date between old.start_date and old.end_date) then
    raise exception 'A period containing posted entries cannot be moved';
  end if;
  if tg_op='UPDATE' and not old.is_closed and new.is_closed
     and exists(select 1 from public.journal_entries e where e.org_id=old.org_id
       and e.entry_date between old.start_date and old.end_date
       and e.status in ('submitted','pending_approval','approved')) then
    raise exception 'Resolve pending journal entries before closing the period';
  end if;
  if tg_op='UPDATE' and new.org_id is distinct from old.org_id then raise exception 'Period organization is immutable'; end if;
  return new;
end;
$$;
revoke all on function private.check_period_range() from public, anon, authenticated;
drop trigger if exists accounting_period_range_guard on public.accounting_periods;
create trigger accounting_period_range_guard before insert or update on public.accounting_periods
  for each row execute function private.check_period_range();

create or replace function private.seed_fiscal_periods()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  first_day date;
  period_start date;
  period_end date;
  year_number integer := extract(year from current_date)::integer;
  month_offset integer;
begin
  if extract(month from current_date)::integer<new.fy_start_month then year_number:=year_number-1; end if;
  first_day:=make_date(year_number,new.fy_start_month,1);
  for month_offset in 0..11 loop
    period_start:=(first_day+make_interval(months=>month_offset))::date;
    period_end:=((first_day+make_interval(months=>month_offset+1))::date-1);
    insert into public.accounting_periods(org_id,start_date,end_date,is_closed)
      values(new.id,period_start,period_end,false);
  end loop;
  return new;
end;
$$;
revoke all on function private.seed_fiscal_periods() from public, anon, authenticated;
drop trigger if exists organization_seed_fiscal_periods on public.organizations;
create trigger organization_seed_fiscal_periods after insert on public.organizations
  for each row execute function private.seed_fiscal_periods();

create or replace function private.assert_open_period(p_org uuid,p_date date)
returns void language plpgsql security definer set search_path = ''
as $$
declare is_closed boolean;
begin
  select p.is_closed into is_closed from public.accounting_periods p
    where p.org_id=p_org and p_date between p.start_date and p.end_date for update;
  if not found then raise exception 'No accounting period covers %',p_date; end if;
  if is_closed then raise exception 'Accounting period is closed'; end if;
end;
$$;

create or replace function private.validate_journal_entry(p_entry uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  e record;
  line_count bigint;
  debit_total numeric(30,4);
  credit_total numeric(30,4);
begin
  select j.org_id,j.entry_date,j.currency,j.exchange_rate,o.base_currency into e
    from public.journal_entries j join public.organizations o on o.id=j.org_id where j.id=p_entry;
  if not found then raise exception 'Journal entry not found'; end if;
  perform private.assert_open_period(e.org_id,e.entry_date);
  select count(*),coalesce(sum(l.debit),0),coalesce(sum(l.credit),0)
    into line_count,debit_total,credit_total from public.journal_lines l where l.entry_id=p_entry;
  if line_count<2 then raise exception 'A journal entry needs at least two lines'; end if;
  if debit_total<>credit_total then raise exception 'Unbalanced entry: debit % does not equal credit %',debit_total,credit_total; end if;
  if e.currency=e.base_currency and e.exchange_rate<>1 then raise exception 'Base-currency entries must use an exchange rate of 1'; end if;
  if exists(select 1 from public.journal_lines l join public.accounts a on a.id=l.account_id
    where l.entry_id=p_entry and not a.is_active) then raise exception 'Entry uses an inactive account'; end if;
end;
$$;
revoke all on function private.assert_open_period(uuid,date) from public, anon, authenticated;
revoke all on function private.validate_journal_entry(uuid) from public, anon, authenticated;

create or replace function public.create_journal_entry_draft(
  p_org uuid,p_entry_date date,p_reference text,p_description text,p_currency char(3),
  p_exchange_rate numeric,p_entry_kind text,p_lines jsonb
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  new_entry uuid;
  item jsonb;
  debit_total numeric(30,4) := 0;
  credit_total numeric(30,4) := 0;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then
    raise exception 'Not authorized to create journal entries';
  end if;
  if nullif(trim(p_description),'') is null then raise exception 'Description is required'; end if;
  if p_exchange_rate is null or p_exchange_rate<=0 then raise exception 'Exchange rate must be positive'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<2 then raise exception 'At least two journal lines are required'; end if;
  for item in select value from jsonb_array_elements(p_lines) loop
    debit_total := debit_total + coalesce(nullif(item->>'debit','')::numeric,0);
    credit_total := credit_total + coalesce(nullif(item->>'credit','')::numeric,0);
  end loop;
  if debit_total<>credit_total then raise exception 'Unbalanced entry: debit % does not equal credit %',debit_total,credit_total; end if;
  insert into public.journal_entries(org_id,entry_date,reference,description,currency,exchange_rate,created_by,entry_kind)
    values(p_org,p_entry_date,nullif(trim(p_reference),''),trim(p_description),p_currency,p_exchange_rate,actor,coalesce(p_entry_kind,'general'))
    returning id into new_entry;
  for item in select value from jsonb_array_elements(p_lines) loop
    insert into public.journal_lines(entry_id,org_id,account_id,debit,credit,memo)
      values(new_entry,p_org,(item->>'account_id')::uuid,
        coalesce(nullif(item->>'debit','')::numeric,0),
        coalesce(nullif(item->>'credit','')::numeric,0),
        nullif(trim(item->>'memo'),''));
  end loop;
  return new_entry;
end;
$$;

-- Secure replacement for the setup RPC: current user owns the new organization and its starter ledger.
create or replace function private.create_organization(
  p_name text,p_legal text,p_country text,p_city text,p_base_currency char(3),
  p_fy_start_month int,p_method text,p_owner_name text
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare org_id uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if nullif(trim(p_name),'') is null then raise exception 'Organization name is required'; end if;
  if p_base_currency !~ '^[A-Z]{3}$' then raise exception 'Base currency must be a three-letter uppercase code'; end if;
  if p_fy_start_month not between 1 and 12 then raise exception 'Financial year start month must be 1 through 12'; end if;
  if p_method not in ('accrual','cash') then raise exception 'Accounting method must be accrual or cash'; end if;
  insert into public.user_profiles(id,full_name) values(auth.uid(),nullif(trim(p_owner_name),''))
    on conflict(id) do update set full_name=excluded.full_name;
  insert into public.organizations(name,legal_name,country,city,base_currency,fy_start_month,accounting_method)
    values(trim(p_name),nullif(trim(p_legal),''),nullif(trim(p_country),''),nullif(trim(p_city),''),p_base_currency,p_fy_start_month,p_method)
    returning id into org_id;
  insert into public.organization_members(org_id,user_id,role) values(org_id,auth.uid(),'owner');
  insert into public.accounts(org_id,code,name,type) values
    (org_id,'1000','Cash','asset'),(org_id,'1100','Bank Accounts','asset'),(org_id,'1200','Accounts Receivable','asset'),
    (org_id,'1300','Prepaid Expenses','asset'),(org_id,'1400','Inventory','asset'),(org_id,'1500','Equipment','asset'),
    (org_id,'1510','Computer Equipment','asset'),(org_id,'1590','Accumulated Depreciation','asset'),
    (org_id,'2000','Accounts Payable','liability'),(org_id,'2100','Salaries Payable','liability'),
    (org_id,'2200','Taxes Payable','liability'),(org_id,'2300','Accrued Expenses','liability'),(org_id,'2500','Loans Payable','liability'),
    (org_id,'3000','Owner''s Capital','equity'),(org_id,'3100','Retained Earnings','equity'),(org_id,'3200','Owner''s Drawings','equity'),
    (org_id,'4000','Service Revenue','revenue'),(org_id,'4100','SEO Revenue','revenue'),(org_id,'4200','Digital Marketing Revenue','revenue'),
    (org_id,'4300','Recruitment Revenue','revenue'),(org_id,'4400','Product Revenue','revenue'),(org_id,'4900','Non-Operating Income','revenue'),
    (org_id,'5000','Salaries and Wages','expense'),(org_id,'5100','Advertising Expenses','expense'),
    (org_id,'5200','Software Subscriptions','expense'),(org_id,'5300','Hosting Expenses','expense'),
    (org_id,'5400','Office Rent','expense'),(org_id,'5500','Internet Expenses','expense'),
    (org_id,'5600','Professional Fees','expense'),(org_id,'5700','Bank Charges','expense'),
    (org_id,'5800','Depreciation','expense'),(org_id,'5900','Miscellaneous Expenses','expense');
  return org_id;
end;
$$;
revoke all on function private.create_organization(text,text,text,text,char,integer,text,text) from public, anon, authenticated;
create or replace function public.create_organization(
  p_name text,p_legal text,p_country text,p_city text,p_base_currency char(3),
  p_fy_start_month int,p_method text,p_owner_name text
) returns uuid language plpgsql security definer set search_path = ''
as $$ begin return private.create_organization(p_name,p_legal,p_country,p_city,p_base_currency,p_fy_start_month,p_method,p_owner_name); end; $$;

create or replace function public.submit_journal_entry(p_entry uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare e public.journal_entries%rowtype;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  select * into e from public.journal_entries where id=p_entry for update;
  if not found then raise exception 'Entry not found'; end if;
  if not private.has_role(e.org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to submit'; end if;
  if e.created_by<>auth.uid() then raise exception 'Only the creator may submit this draft'; end if;
  if e.status<>'draft' then raise exception 'Only draft entries can be submitted'; end if;
  perform private.validate_journal_entry(p_entry);
  update public.journal_entries set status='submitted',submitted_at=now() where id=p_entry;
end;
$$;

create or replace function public.queue_journal_entry(p_entry uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare e public.journal_entries%rowtype;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  select * into e from public.journal_entries where id=p_entry for update;
  if not found then raise exception 'Entry not found'; end if;
  if not private.has_role(e.org_id,array['owner','administrator','finance_manager','approver']::public.member_role[]) then raise exception 'Not authorized to queue entries'; end if;
  if e.created_by=auth.uid() then raise exception 'Maker-checker: the creator cannot queue their own entry'; end if;
  if e.status<>'submitted' then raise exception 'Only submitted entries can be queued'; end if;
  update public.journal_entries set status='pending_approval' where id=p_entry;
end;
$$;

create or replace function public.approve_journal_entry(p_entry uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare e public.journal_entries%rowtype;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  select * into e from public.journal_entries where id=p_entry for update;
  if not found then raise exception 'Entry not found'; end if;
  if not private.has_role(e.org_id,array['owner','administrator','finance_manager','approver']::public.member_role[]) then raise exception 'Not authorized to approve'; end if;
  if e.status<>'pending_approval' then raise exception 'Only pending entries can be approved'; end if;
  if e.created_by=auth.uid() then raise exception 'Maker-checker: you cannot approve your own entry'; end if;
  perform private.validate_journal_entry(p_entry);
  update public.journal_entries set status='approved',approved_by=auth.uid() where id=p_entry;
end;
$$;

create or replace function public.reject_journal_entry(p_entry uuid,p_reason text)
returns void language plpgsql security definer set search_path = ''
as $$
declare e public.journal_entries%rowtype;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if nullif(trim(p_reason),'') is null then raise exception 'A rejection reason is required'; end if;
  if length(trim(p_reason))>2000 then raise exception 'Rejection reason must be at most 2000 characters'; end if;
  select * into e from public.journal_entries where id=p_entry for update;
  if not found then raise exception 'Entry not found'; end if;
  if not private.has_role(e.org_id,array['owner','administrator','finance_manager','approver']::public.member_role[]) then raise exception 'Not authorized to reject'; end if;
  if e.created_by=auth.uid() then raise exception 'Maker-checker: the creator cannot reject their own entry'; end if;
  if e.status not in ('submitted','pending_approval') then raise exception 'Only submitted or pending entries can be rejected'; end if;
  update public.journal_entries set status='draft',submitted_at=null,rejected_at=now(),rejected_by=auth.uid(),
    rejection_reason=trim(p_reason) where id=p_entry;
end;
$$;

create or replace function public.post_journal_entry(p_entry uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare e public.journal_entries%rowtype;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  select * into e from public.journal_entries where id=p_entry for update;
  if not found then raise exception 'Entry not found'; end if;
  if not private.has_role(e.org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to post'; end if;
  if e.status<>'approved' or e.approved_by is null or e.approved_by=e.created_by then
    raise exception 'Only an entry approved by a different authorized user can be posted';
  end if;
  perform private.validate_journal_entry(p_entry);
  update public.journal_entries set status='posted',posted_at=now() where id=p_entry;
  if e.reverses_id is not null then
    update public.journal_entries set status='reversed' where id=e.reverses_id and org_id=e.org_id and status='posted';
    if not found then raise exception 'The source entry is no longer posted'; end if;
  end if;
end;
$$;

create or replace function public.reverse_journal_entry(p_entry uuid,p_date date default current_date,p_reason text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare source_entry public.journal_entries%rowtype; reversal_id uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if nullif(trim(p_reason),'') is null then raise exception 'A reversal reason is required'; end if;
  if length(trim(p_reason))>2000 then raise exception 'Reversal reason must be at most 2000 characters'; end if;
  select * into source_entry from public.journal_entries where id=p_entry for update;
  if not found then raise exception 'Entry not found'; end if;
  if not private.has_role(source_entry.org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to reverse'; end if;
  if source_entry.status<>'posted' then raise exception 'Only posted entries can be reversed'; end if;
  perform private.assert_open_period(source_entry.org_id,p_date);
  insert into public.journal_entries(org_id,entry_date,reference,description,currency,exchange_rate,entry_kind,reverses_id,reversal_reason)
    values(source_entry.org_id,p_date,source_entry.entry_no,'Reversal of '||source_entry.entry_no,
      source_entry.currency,source_entry.exchange_rate,'reversal',source_entry.id,trim(p_reason))
    returning id into reversal_id;
  insert into public.journal_lines(entry_id,org_id,account_id,debit,credit,memo)
    select reversal_id,l.org_id,l.account_id,l.credit,l.debit,l.memo from public.journal_lines l where l.entry_id=source_entry.id;
  return reversal_id;
end;
$$;

create or replace function public.set_organization_member_role(p_org uuid,p_user uuid,p_role public.member_role)
returns void language plpgsql security definer set search_path = ''
as $$
declare actor_role public.member_role; target_role public.member_role; owner_count bigint;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_org::text,1));
  select role into actor_role from public.organization_members where org_id=p_org and user_id=auth.uid();
  select role into target_role from public.organization_members where org_id=p_org and user_id=p_user for update;
  if actor_role not in ('owner','administrator') or target_role is null then raise exception 'Not authorized or member not found'; end if;
  if actor_role='administrator' and (target_role in ('owner','administrator') or p_role in ('owner','administrator')) then
    raise exception 'Only the owner can change owner or administrator roles';
  end if;
  if target_role='owner' and p_role<>'owner' then
    select count(*) into owner_count from public.organization_members where org_id=p_org and role='owner';
    if owner_count<=1 then raise exception 'An organization must retain at least one owner'; end if;
  end if;
  update public.organization_members set role=p_role where org_id=p_org and user_id=p_user;
end;
$$;
create or replace function public.add_organization_member(p_org uuid,p_user uuid,p_role public.member_role)
returns void language plpgsql security definer set search_path = ''
as $$
declare actor_role public.member_role;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_org::text,1));
  select role into actor_role from public.organization_members where org_id=p_org and user_id=auth.uid();
  if actor_role not in ('owner','administrator') then raise exception 'Not authorized to add organization members'; end if;
  if actor_role='administrator' and p_role in ('owner','administrator') then raise exception 'Only the owner can assign owner or administrator roles'; end if;
  insert into public.organization_members(org_id,user_id,role) values(p_org,p_user,p_role);
end;
$$;
create or replace function public.remove_organization_member(p_org uuid,p_user uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare actor_role public.member_role; target_role public.member_role; owner_count bigint;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_org::text,1));
  select role into actor_role from public.organization_members where org_id=p_org and user_id=auth.uid();
  select role into target_role from public.organization_members where org_id=p_org and user_id=p_user for update;
  if actor_role not in ('owner','administrator') or target_role is null then raise exception 'Not authorized or member not found'; end if;
  if actor_role='administrator' and target_role in ('owner','administrator') then raise exception 'Only the owner can remove an owner or administrator'; end if;
  if target_role='owner' then
    select count(*) into owner_count from public.organization_members where org_id=p_org and role='owner';
    if owner_count<=1 then raise exception 'An organization must retain at least one owner'; end if;
  end if;
  delete from public.organization_members where org_id=p_org and user_id=p_user;
end;
$$;

create or replace function public.trial_balance(p_org uuid,p_from date,p_to date)
returns table(code text,name text,type public.account_type,debit numeric,credit numeric)
language sql stable security invoker set search_path = ''
as $$
  select a.code,a.name,a.type,greatest(coalesce(sum(l.base_debit-l.base_credit),0),0),
    greatest(-coalesce(sum(l.base_debit-l.base_credit),0),0)
  from public.accounts a
  left join public.journal_entries e on e.org_id=a.org_id
    and e.status in ('posted','reversed') and e.entry_date between p_from and p_to
  left join public.journal_lines l on l.account_id=a.id and l.org_id=a.org_id and l.entry_id=e.id
  where a.org_id=p_org group by a.id,a.code,a.name,a.type order by a.code;
$$;
create or replace function public.trial_balance_as_of(p_org uuid,p_as_of date)
returns table(code text,name text,type public.account_type,debit numeric,credit numeric)
language sql stable security invoker set search_path = ''
as $$
  select a.code,a.name,a.type,greatest(coalesce(sum(l.base_debit-l.base_credit),0),0),
    greatest(-coalesce(sum(l.base_debit-l.base_credit),0),0)
  from public.accounts a
  left join public.journal_entries e on e.org_id=a.org_id
    and e.status in ('posted','reversed') and e.entry_date<=p_as_of
  left join public.journal_lines l on l.account_id=a.id and l.org_id=a.org_id and l.entry_id=e.id
  where a.org_id=p_org group by a.id,a.code,a.name,a.type order by a.code;
$$;
create or replace function public.profit_and_loss(p_org uuid,p_from date,p_to date)
returns table(code text,name text,type public.account_type,amount numeric)
language sql stable security invoker set search_path = ''
as $$
  select a.code,a.name,a.type,
    case when a.type='revenue' then coalesce(sum(l.base_credit-l.base_debit),0)
         else coalesce(sum(l.base_debit-l.base_credit),0) end
  from public.accounts a
  left join public.journal_entries e on e.org_id=a.org_id
    and e.status in ('posted','reversed') and e.entry_date between p_from and p_to
  left join public.journal_lines l on l.account_id=a.id and l.org_id=a.org_id and l.entry_id=e.id
  where a.org_id=p_org and a.type in ('revenue','expense')
  group by a.id,a.code,a.name,a.type order by a.code;
$$;
create or replace function public.balance_sheet(p_org uuid,p_as_of date)
returns table(section text,code text,name text,balance numeric)
language sql stable security invoker set search_path = ''
as $$
  with account_balances as (
    select a.id,a.code,a.name,a.type,
      case when a.type='asset' then coalesce(sum(l.base_debit-l.base_credit),0)
           else coalesce(sum(l.base_credit-l.base_debit),0) end as balance
    from public.accounts a
    left join public.journal_entries e on e.org_id=a.org_id
      and e.status in ('posted','reversed') and e.entry_date<=p_as_of
    left join public.journal_lines l on l.account_id=a.id and l.org_id=a.org_id and l.entry_id=e.id
    where a.org_id=p_org and a.type in ('asset','liability','equity')
    group by a.id,a.code,a.name,a.type
  ), current_earnings as (
    select coalesce(sum(case when a.type in ('revenue','expense') then l.base_credit-l.base_debit else 0 end),0) amount
    from public.accounts a join public.journal_lines l on l.account_id=a.id and l.org_id=a.org_id
    join public.journal_entries e on e.id=l.entry_id and e.org_id=l.org_id
    where a.org_id=p_org and a.type in ('revenue','expense') and e.status in ('posted','reversed') and e.entry_date<=p_as_of
  )
  select case b.type when 'asset' then 'assets' when 'liability' then 'liabilities' else 'equity' end,
    b.code,b.name,b.balance from account_balances b
  union all select 'equity','3999','Current earnings',amount from current_earnings where amount<>0
  order by 1,2;
$$;

create or replace function public.financial_summary(p_org uuid,p_from date,p_to date,p_as_of date)
returns table(income numeric,expenses numeric,profit numeric,assets numeric,liabilities numeric,equity numeric,
  cash_balance numeric,bank_balance numeric,accounts_receivable numeric,accounts_payable numeric)
language sql stable security invoker set search_path = ''
as $$
  with period_pl as (
    select coalesce(sum(amount) filter(where type='revenue'),0) as income,
      coalesce(sum(amount) filter(where type='expense'),0) as expenses
    from public.profit_and_loss(p_org,p_from,p_to)
  ),
  lifetime_pl as (
    select coalesce(sum(amount) filter(where type='revenue'),0) as income,
      coalesce(sum(amount) filter(where type='expense'),0) as expenses
    from public.profit_and_loss(p_org,date '0001-01-01',p_as_of)
  ),
  balances as (
    select t.code,t.name,t.type,
      case when t.type in ('asset','expense') then t.debit-t.credit else t.credit-t.debit end as value
    from public.trial_balance_as_of(p_org,p_as_of) t
  ),
  sums as (
    select coalesce(sum(value) filter(where type='asset'),0) assets,
      coalesce(sum(value) filter(where type='liability'),0) liabilities,
      coalesce(sum(value) filter(where type='equity'),0) equity,
      coalesce(sum(value) filter(where type='asset' and (lower(name) like '%cash%' or code='1000')),0) cash_balance,
      coalesce(sum(value) filter(where type='asset' and lower(name) like '%bank%'),0) bank_balance,
      coalesce(sum(value) filter(where type='asset' and lower(name) like '%receivable%'),0) accounts_receivable,
      coalesce(sum(value) filter(where type='liability' and lower(name) like '%payable%'),0) accounts_payable
    from balances
  )
  select p.income,p.expenses,p.income-p.expenses,s.assets,s.liabilities,s.equity+lp.income-lp.expenses,
    s.cash_balance,s.bank_balance,s.accounts_receivable,s.accounts_payable
  from period_pl p cross join sums s cross join lifetime_pl lp;
$$;

create or replace function public.monthly_financial_activity(p_org uuid,p_from date)
returns table(month_start date,revenue numeric,expenses numeric)
language sql stable security invoker set search_path = ''
as $$
  with months as (
    select generate_series(date_trunc('month',p_from)::date,date_trunc('month',current_date)::date,interval '1 month')::date as month_start
  ), activity as (
    select date_trunc('month',e.entry_date)::date as month_start,
      coalesce(sum(l.base_credit-l.base_debit) filter(where a.type='revenue'),0) as revenue,
      coalesce(sum(l.base_debit-l.base_credit) filter(where a.type='expense'),0) as expenses
    from public.journal_entries e join public.journal_lines l on l.entry_id=e.id and l.org_id=e.org_id
      join public.accounts a on a.id=l.account_id and a.org_id=l.org_id
    where e.org_id=p_org and e.status in ('posted','reversed') and e.entry_date>=date_trunc('month',p_from)::date
      and a.type in ('revenue','expense')
    group by 1
  )
  select m.month_start,coalesce(a.revenue,0),coalesce(a.expenses,0) from months m left join activity a using(month_start) order by m.month_start;
$$;

drop view if exists public.ledger;
create view public.ledger with (security_invoker=true) as
select l.org_id,a.id as account_id,a.code,a.name as account_name,e.id as entry_id,e.entry_no,
  e.entry_date,e.description,l.memo,l.base_debit as debit,l.base_credit as credit,
  sum(case when a.normal_balance='debit' then l.base_debit-l.base_credit
           else l.base_credit-l.base_debit end)
    over(partition by l.account_id order by e.entry_date,e.entry_no,l.id) as running_balance,
  e.currency,e.exchange_rate,l.debit as transaction_debit,l.credit as transaction_credit
from public.journal_lines l
join public.journal_entries e on e.id=l.entry_id and e.org_id=l.org_id
join public.accounts a on a.id=l.account_id and a.org_id=l.org_id
where e.status in ('posted','reversed');

create or replace function public.trg_account_org_guard()
returns trigger language plpgsql set search_path = ''
as $$ begin
  if new.id is distinct from old.id or new.org_id is distinct from old.org_id then raise exception 'Account identity and organization are immutable'; end if;
  if (new.type,new.code,new.name,new.parent_id) is distinct from (old.type,old.code,old.name,old.parent_id)
     and exists(select 1 from public.journal_lines l join public.journal_entries e on e.id=l.entry_id and e.org_id=l.org_id
       where l.account_id=old.id and e.status in ('posted','reversed')) then
    raise exception 'Accounts referenced by posted entries cannot change code, name, type, or parent';
  end if;
  return new;
end; $$;
drop trigger if exists account_org_guard on public.accounts;
create trigger account_org_guard before update on public.accounts for each row execute function public.trg_account_org_guard();

create or replace function public.trg_org_guard()
returns trigger language plpgsql set search_path = ''
as $$ begin
  if new.id is distinct from old.id then raise exception 'Organization identity is immutable'; end if;
  if new.journal_seq is distinct from old.journal_seq and current_user<>'postgres' then raise exception 'Journal sequence is database-managed'; end if;
  if (new.base_currency,new.fy_start_month,new.accounting_method) is distinct from (old.base_currency,old.fy_start_month,old.accounting_method)
     and exists(select 1 from public.journal_entries e where e.org_id=old.id) then
    raise exception 'Accounting basis and fiscal year cannot change after journal activity exists';
  end if;
  return new;
end; $$;
drop trigger if exists organization_identity_guard on public.organizations;
create trigger organization_identity_guard before update on public.organizations for each row execute function public.trg_org_guard();

create or replace function public.trg_member_guard()
returns trigger language plpgsql set search_path = ''
as $$
declare actor_role public.member_role; owner_count bigint; target_org uuid;
begin
  if current_user='postgres' then if tg_op='DELETE' then return old; else return new; end if; end if;
  if tg_op='DELETE' then target_org:=old.org_id; else target_org:=new.org_id; end if;
  select role into actor_role from public.organization_members where org_id=target_org and user_id=auth.uid();
  if tg_op='INSERT' then
    if actor_role not in ('owner','administrator') then raise exception 'Not authorized to add members'; end if;
    if actor_role='administrator' and new.role in ('owner','administrator') then raise exception 'Only the owner may assign owner or administrator roles'; end if;
    return new;
  end if;
  if tg_op='UPDATE' then
    if new.org_id is distinct from old.org_id or new.user_id is distinct from old.user_id then raise exception 'Membership identity is immutable'; end if;
    if actor_role not in ('owner','administrator') then raise exception 'Not authorized to change memberships'; end if;
    if actor_role='administrator' and (old.role in ('owner','administrator') or new.role in ('owner','administrator')) then
      raise exception 'Only the owner may change owner or administrator roles';
    end if;
    if old.role='owner' and new.role<>'owner' then
      select count(*) into owner_count from public.organization_members where org_id=old.org_id and role='owner';
      if owner_count<=1 then raise exception 'An organization must retain at least one owner'; end if;
    end if;
    return new;
  end if;
  if actor_role not in ('owner','administrator') then raise exception 'Not authorized to remove members'; end if;
  if actor_role='administrator' and old.role in ('owner','administrator') then raise exception 'Only the owner may remove an owner or administrator'; end if;
  if old.role='owner' then
    select count(*) into owner_count from public.organization_members where org_id=old.org_id and role='owner';
    if owner_count<=1 then raise exception 'An organization must retain at least one owner'; end if;
  end if;
  return old;
end;
$$;
drop trigger if exists member_guard on public.organization_members;
create trigger member_guard before insert or update or delete on public.organization_members for each row execute function public.trg_member_guard();

drop policy if exists members_manage on public.organization_members;
drop policy if exists members_read on public.organization_members;
create policy members_read on public.organization_members for select to authenticated using (private.is_member(org_id));

drop policy if exists acct_read on public.accounts;
drop policy if exists acct_write on public.accounts;
create policy acct_read on public.accounts for select to authenticated
  using (private.has_role(org_id,array['owner','administrator','accountant','finance_manager','approver','auditor','viewer']::public.member_role[]));
create policy acct_insert on public.accounts for insert to authenticated
  with check (private.has_role(org_id,array['owner','administrator','accountant']::public.member_role[]));
create policy acct_update on public.accounts for update to authenticated
  using (private.has_role(org_id,array['owner','administrator','accountant']::public.member_role[]))
  with check (private.has_role(org_id,array['owner','administrator','accountant']::public.member_role[]));

drop policy if exists period_read on public.accounting_periods;
drop policy if exists period_write on public.accounting_periods;
create policy period_read on public.accounting_periods for select to authenticated using (private.is_member(org_id));
create policy period_insert on public.accounting_periods for insert to authenticated
  with check (private.has_role(org_id,array['owner','finance_manager']::public.member_role[]));
create policy period_update on public.accounting_periods for update to authenticated
  using (private.has_role(org_id,array['owner','finance_manager']::public.member_role[]))
  with check (private.has_role(org_id,array['owner','finance_manager']::public.member_role[]));

drop policy if exists je_read on public.journal_entries;
drop policy if exists je_insert on public.journal_entries;
drop policy if exists je_update on public.journal_entries;
drop policy if exists je_delete on public.journal_entries;
create policy je_read on public.journal_entries for select to authenticated
  using (private.has_role(org_id,array['owner','administrator','accountant','finance_manager','approver','auditor','viewer']::public.member_role[]));
create policy je_insert on public.journal_entries for insert to authenticated
  with check (private.has_role(org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[])
    and created_by=auth.uid() and status='draft');
create policy je_update on public.journal_entries for update to authenticated
  using (status='draft' and created_by=auth.uid() and private.has_role(org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[]))
  with check (status='draft' and created_by=auth.uid() and private.has_role(org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[]));
create policy je_delete on public.journal_entries for delete to authenticated
  using (status='draft' and created_by=auth.uid() and private.has_role(org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[]));

drop policy if exists jl_read on public.journal_lines;
drop policy if exists jl_write on public.journal_lines;
create policy jl_read on public.journal_lines for select to authenticated
  using (private.has_role(org_id,array['owner','administrator','accountant','finance_manager','approver','auditor','viewer']::public.member_role[]));
create policy jl_insert on public.journal_lines for insert to authenticated
  with check (private.has_role(org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[])
    and exists(select 1 from public.journal_entries e where e.id=journal_lines.entry_id and e.org_id=journal_lines.org_id and e.status='draft' and e.created_by=auth.uid()));
create policy jl_update on public.journal_lines for update to authenticated
  using (private.has_role(org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[])
    and exists(select 1 from public.journal_entries e where e.id=journal_lines.entry_id and e.org_id=journal_lines.org_id and e.status='draft' and e.created_by=auth.uid()))
  with check (private.has_role(org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[])
    and exists(select 1 from public.journal_entries e where e.id=journal_lines.entry_id and e.org_id=journal_lines.org_id and e.status='draft' and e.created_by=auth.uid()));
create policy jl_delete on public.journal_lines for delete to authenticated
  using (private.has_role(org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[])
    and exists(select 1 from public.journal_entries e where e.id=journal_lines.entry_id and e.org_id=journal_lines.org_id and e.status='draft' and e.created_by=auth.uid()));

drop policy if exists audit_read on public.audit_logs;
create policy audit_read on public.audit_logs for select to authenticated
  using (private.has_role(org_id,array['owner','administrator','auditor','viewer']::public.member_role[]));
drop policy if exists org_read on public.organizations;
drop policy if exists org_update on public.organizations;
create policy org_read on public.organizations for select to authenticated using (private.is_member(id));
create policy org_update on public.organizations for update to authenticated
  using (private.has_role(id,array['owner']::public.member_role[]))
  with check (private.has_role(id,array['owner']::public.member_role[]));

revoke all on all tables in schema public from anon;
revoke all on public.audit_logs from anon,authenticated;
grant select on public.organizations,public.organization_members,public.accounts,public.accounting_periods,
  public.journal_entries,public.journal_lines,public.audit_logs to authenticated;
grant select,insert,update on public.user_profiles to authenticated;
grant update on public.organizations to authenticated;
grant insert,update on public.accounts,public.accounting_periods to authenticated;
grant insert,update,delete on public.journal_entries,public.journal_lines to authenticated;
grant select on public.ledger to authenticated;
grant select on public.audit_logs to authenticated;

revoke execute on all functions in schema public from public,anon;
grant execute on function public.is_member(uuid) to authenticated;
grant execute on function public.has_role(uuid,public.member_role[]) to authenticated;
grant execute on function public.create_organization(text,text,text,text,char,integer,text,text) to authenticated;
grant execute on function public.create_journal_entry_draft(uuid,date,text,text,char,numeric,text,jsonb) to authenticated;
grant execute on function public.submit_journal_entry(uuid) to authenticated;
grant execute on function public.queue_journal_entry(uuid) to authenticated;
grant execute on function public.approve_journal_entry(uuid) to authenticated;
grant execute on function public.reject_journal_entry(uuid,text) to authenticated;
grant execute on function public.post_journal_entry(uuid) to authenticated;
grant execute on function public.reverse_journal_entry(uuid,date,text) to authenticated;
grant execute on function public.set_organization_member_role(uuid,uuid,public.member_role) to authenticated;
grant execute on function public.add_organization_member(uuid,uuid,public.member_role) to authenticated;
grant execute on function public.remove_organization_member(uuid,uuid) to authenticated;
grant execute on function public.trial_balance(uuid,date,date) to authenticated;
grant execute on function public.trial_balance_as_of(uuid,date) to authenticated;
grant execute on function public.profit_and_loss(uuid,date,date) to authenticated;
grant execute on function public.balance_sheet(uuid,date) to authenticated;
grant execute on function public.financial_summary(uuid,date,date,date) to authenticated;
grant execute on function public.monthly_financial_activity(uuid,date) to authenticated;

alter default privileges for role postgres in schema public revoke all on tables from anon,authenticated;
alter default privileges for role postgres in schema public revoke execute on functions from public,anon,authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon,authenticated;
