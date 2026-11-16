-- Linkora Finance: Phase 1+2 (foundation, RBAC, chart of accounts, double-entry engine)
create extension if not exists pgcrypto;

create type member_role as enum ('owner','administrator','accountant','finance_manager','auditor','employee');
create type account_type as enum ('asset','liability','equity','revenue','expense');
create type entry_status as enum ('draft','approved','posted','reversed');

create table organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null, legal_name text, country text, city text,
  base_currency char(3) not null default 'PKR',
  fy_start_month int not null default 1 check (fy_start_month between 1 and 12),
  accounting_method text not null default 'accrual' check (accounting_method in ('accrual','cash')),
  require_approval boolean not null default true,
  journal_seq bigint not null default 0,
  created_at timestamptz not null default now()
);
create table user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text, created_at timestamptz not null default now()
);
create table organization_members (
  org_id uuid not null references organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role member_role not null,
  primary key (org_id, user_id)
);
create table accounts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id),
  code text not null, name text not null, description text,
  type account_type not null,
  normal_balance text generated always as (case when type in ('asset','expense') then 'debit' else 'credit' end) stored,
  parent_id uuid references accounts(id),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (org_id, code)
);
create table accounting_periods (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id),
  start_date date not null, end_date date not null,
  is_closed boolean not null default false,
  check (end_date >= start_date)
);
create table journal_entries (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id),
  entry_no text, entry_date date not null,
  reference text, description text not null,
  currency char(3) not null default 'PKR',
  exchange_rate numeric(18,8) not null default 1 check (exchange_rate > 0),
  status entry_status not null default 'draft',
  created_by uuid not null default auth.uid() references auth.users(id),
  approved_by uuid references auth.users(id),
  posted_at timestamptz,
  reverses_id uuid references journal_entries(id),
  created_at timestamptz not null default now(),
  unique (org_id, entry_no)
);
create table journal_lines (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references journal_entries(id),
  org_id uuid not null references organizations(id),
  account_id uuid not null references accounts(id),
  debit numeric(20,4) not null default 0 check (debit >= 0),
  credit numeric(20,4) not null default 0 check (credit >= 0),
  memo text,
  check ((debit = 0) <> (credit = 0))   -- exactly one side, non-zero
);
create table audit_logs (
  id bigint generated always as identity primary key,
  org_id uuid, user_id uuid, action text not null,
  entity_type text not null, entity_id uuid,
  old_values jsonb, new_values jsonb, at timestamptz not null default now()
);
create index on journal_lines (org_id, account_id);
create index on journal_lines (entry_id);
create index on journal_entries (org_id, entry_date);
create index on audit_logs (org_id, at desc);

-- ---------- access helpers ----------
create function is_member(p_org uuid) returns boolean language sql stable security definer set search_path=public as
$$ select exists (select 1 from organization_members where org_id=p_org and user_id=auth.uid()) $$;
create function has_role(p_org uuid, p_roles member_role[]) returns boolean language sql stable security definer set search_path=public as
$$ select exists (select 1 from organization_members where org_id=p_org and user_id=auth.uid() and role = any(p_roles)) $$;

-- ---------- integrity triggers ----------
create function trg_entry_guard() returns trigger language plpgsql as $$
begin
  if tg_op='DELETE' then
    if old.status <> 'draft' then raise exception 'Posted/approved entries cannot be deleted; use a reversal'; end if;
    return old;
  end if;
  if tg_op='INSERT' then
    if new.status <> 'draft' and coalesce(current_setting('app.posting',true),'')<>'on' then
      raise exception 'Entries must be created as draft'; end if;
    return new;
  end if;
  if old.status in ('posted','reversed') and coalesce(current_setting('app.posting',true),'')<>'on' then
    raise exception 'Posted entries are immutable; use a reversing entry';
  end if;
  return new;
end $$;
create trigger entry_guard before insert or update or delete on journal_entries for each row execute function trg_entry_guard();

create function trg_entry_number() returns trigger language plpgsql as $$
declare n bigint;
begin
  update organizations set journal_seq = journal_seq + 1 where id=new.org_id returning journal_seq into n;
  new.entry_no := 'JE-' || lpad(n::text, 6, '0'); return new;
end $$;
create trigger entry_number before insert on journal_entries for each row execute function trg_entry_number();

create function trg_line_guard() returns trigger language plpgsql as $$
declare s entry_status; e uuid; o uuid;
begin
  e := coalesce(new.entry_id, old.entry_id);
  select status, org_id into s, o from journal_entries where id=e;
  if s in ('posted','reversed') then raise exception 'Lines of a posted entry cannot be changed'; end if;
  if tg_op <> 'DELETE' and new.org_id <> o then raise exception 'Line org must match entry org'; end if;
  if tg_op <> 'DELETE' and not exists (select 1 from accounts a where a.id=new.account_id and a.org_id=o) then
    raise exception 'Account does not belong to this organization'; end if;
  return coalesce(new, old);
end $$;
create trigger line_guard before insert or update or delete on journal_lines for each row execute function trg_line_guard();

create function trg_audit() returns trigger language plpgsql security definer set search_path=public as $$
declare r record; oid uuid;
begin
  r := coalesce(new, old);
  oid := case when tg_table_name='organizations' then r.id else r.org_id end;
  insert into audit_logs(org_id,user_id,action,entity_type,entity_id,old_values,new_values)
  values (oid, auth.uid(), tg_op, tg_table_name, r.id,
          case when tg_op<>'INSERT' then to_jsonb(old) end,
          case when tg_op<>'DELETE' then to_jsonb(new) end);
  return r;
end $$;
create trigger audit_accounts after insert or update on accounts for each row execute function trg_audit();
create trigger audit_entries  after insert or update on journal_entries for each row execute function trg_audit();
create trigger audit_orgs     after update on organizations for each row execute function trg_audit();

-- ---------- posting engine (all-or-nothing) ----------
create function approve_journal_entry(p_entry uuid) returns void language plpgsql security definer set search_path=public as $$
declare e journal_entries;
begin
  select * into e from journal_entries where id=p_entry for update;
  if not found then raise exception 'Entry not found'; end if;
  if not has_role(e.org_id, array['owner','administrator','finance_manager']::member_role[]) then raise exception 'Not authorized to approve'; end if;
  if e.status <> 'draft' then raise exception 'Only draft entries can be approved'; end if;
  if e.created_by = auth.uid() then raise exception 'Maker-checker: you cannot approve your own entry'; end if;
  update journal_entries set status='approved', approved_by=auth.uid() where id=p_entry;
end $$;

create function post_journal_entry(p_entry uuid) returns void language plpgsql security definer set search_path=public as $$
declare e journal_entries; d numeric; c numeric; n int;
begin
  select * into e from journal_entries where id=p_entry for update;
  if not found then raise exception 'Entry not found'; end if;
  if not has_role(e.org_id, array['owner','administrator','accountant','finance_manager']::member_role[]) then raise exception 'Not authorized to post'; end if;
  if e.status not in ('draft','approved') then raise exception 'Entry already %', e.status; end if;
  if (select require_approval from organizations where id=e.org_id) and (e.status <> 'approved' or e.approved_by is null or e.approved_by = e.created_by) then
    raise exception 'Entry requires approval by a different user before posting'; end if;
  select coalesce(sum(debit),0), coalesce(sum(credit),0), count(*) into d,c,n from journal_lines where entry_id=p_entry;
  if n < 2 then raise exception 'An entry needs at least two lines'; end if;
  if round(d,4) <> round(c,4) then raise exception 'Unbalanced entry: debits % <> credits %', d, c; end if;
  if exists (select 1 from journal_lines l join accounts a on a.id=l.account_id where l.entry_id=p_entry and not a.is_active) then
    raise exception 'Entry uses an inactive account'; end if;
  if exists (select 1 from accounting_periods p where p.org_id=e.org_id and p.is_closed and e.entry_date between p.start_date and p.end_date) then
    raise exception 'Accounting period is closed'; end if;
  perform set_config('app.posting','on',true);
  update journal_entries set status='posted', posted_at=now() where id=p_entry;
  perform set_config('app.posting','off',true);
end $$;

create function reverse_journal_entry(p_entry uuid, p_date date default current_date, p_reason text default null) returns uuid language plpgsql security definer set search_path=public as $$
declare e journal_entries; r uuid;
begin
  select * into e from journal_entries where id=p_entry for update;
  if not found then raise exception 'Entry not found'; end if;
  if not has_role(e.org_id, array['owner','administrator','finance_manager','accountant']::member_role[]) then raise exception 'Not authorized to reverse'; end if;
  if e.status <> 'posted' then raise exception 'Only posted entries can be reversed'; end if;
  if exists (select 1 from accounting_periods p where p.org_id=e.org_id and p.is_closed and p_date between p.start_date and p.end_date) then
    raise exception 'Accounting period is closed'; end if;
  insert into journal_entries(org_id,entry_date,reference,description,currency,exchange_rate,reverses_id)
  values (e.org_id,p_date,e.entry_no,'Reversal of '||e.entry_no||coalesce(': '||p_reason,''),e.currency,e.exchange_rate,e.id) returning id into r;
  insert into journal_lines(entry_id,org_id,account_id,debit,credit,memo)
    select r,org_id,account_id,credit,debit,memo from journal_lines where entry_id=e.id;
  perform set_config('app.posting','on',true);
  update journal_entries set status='posted', approved_by=auth.uid(), posted_at=now() where id=r;
  update journal_entries set status='reversed' where id=e.id;
  perform set_config('app.posting','off',true);
  return r;
end $$;

-- ---------- reporting source of truth (posted entries only) ----------
create view ledger with (security_invoker=true) as
select l.org_id, a.id account_id, a.code, a.name account_name, e.id entry_id, e.entry_no, e.entry_date,
       e.description, l.memo, l.debit, l.credit,
       sum(case when a.normal_balance='debit' then l.debit-l.credit else l.credit-l.debit end)
         over (partition by l.account_id order by e.entry_date, e.entry_no, l.id) running_balance
from journal_lines l join journal_entries e on e.id=l.entry_id join accounts a on a.id=l.account_id
where e.status in ('posted','reversed');

create function trial_balance(p_org uuid, p_from date, p_to date)
returns table(code text, name text, type account_type, debit numeric, credit numeric)
language sql stable security invoker set search_path=public as $$
  select a.code, a.name, a.type,
         case when sum(l.debit-l.credit) > 0 then sum(l.debit-l.credit) else 0 end,
         case when sum(l.debit-l.credit) < 0 then -sum(l.debit-l.credit) else 0 end
  from accounts a
  join journal_lines l on l.account_id=a.id
  join journal_entries e on e.id=l.entry_id and e.status in ('posted','reversed') and e.entry_date between p_from and p_to
  where a.org_id=p_org group by a.id order by a.code $$;

-- ---------- RLS ----------
alter table organizations enable row level security;
alter table user_profiles enable row level security;
alter table organization_members enable row level security;
alter table accounts enable row level security;
alter table accounting_periods enable row level security;
alter table journal_entries enable row level security;
alter table journal_lines enable row level security;
alter table audit_logs enable row level security;

create policy org_read on organizations for select using (is_member(id));
create policy org_update on organizations for update using (has_role(id, array['owner']::member_role[]));
create policy profile_self on user_profiles for all using (id=auth.uid()) with check (id=auth.uid());
create policy members_read on organization_members for select using (is_member(org_id));
create policy members_manage on organization_members for all
  using (has_role(org_id, array['owner','administrator']::member_role[]))
  with check (has_role(org_id, array['owner','administrator']::member_role[]) and (role <> 'owner' or has_role(org_id, array['owner']::member_role[])));
create policy acct_read on accounts for select using (is_member(org_id) and not has_role(org_id, array['employee']::member_role[]));
create policy acct_write on accounts for all using (has_role(org_id, array['owner','administrator','accountant']::member_role[]))
  with check (has_role(org_id, array['owner','administrator','accountant']::member_role[]));
create policy period_read on accounting_periods for select using (is_member(org_id));
create policy period_write on accounting_periods for all using (has_role(org_id, array['owner','finance_manager']::member_role[]))
  with check (has_role(org_id, array['owner','finance_manager']::member_role[]));
create policy je_read on journal_entries for select using (has_role(org_id, array['owner','administrator','accountant','finance_manager','auditor']::member_role[]));
create policy je_insert on journal_entries for insert with check (has_role(org_id, array['owner','administrator','accountant','finance_manager']::member_role[]) and created_by=auth.uid());
create policy je_update on journal_entries for update using (status='draft' and has_role(org_id, array['owner','administrator','accountant','finance_manager']::member_role[]));
create policy je_delete on journal_entries for delete using (status='draft' and created_by=auth.uid());
create policy jl_read on journal_lines for select using (has_role(org_id, array['owner','administrator','accountant','finance_manager','auditor']::member_role[]));
create policy jl_write on journal_lines for all using (has_role(org_id, array['owner','administrator','accountant','finance_manager']::member_role[]))
  with check (has_role(org_id, array['owner','administrator','accountant','finance_manager']::member_role[]));
create policy audit_read on audit_logs for select using (has_role(org_id, array['owner','administrator','auditor']::member_role[]));
revoke update, delete, insert on audit_logs from anon, authenticated;   -- append-only; written by security-definer triggers
revoke all on all tables in schema public from anon;

-- ---------- setup wizard RPC (creates org, owner membership, starter COA) ----------
create function create_organization(p_name text, p_legal text, p_country text, p_city text,
  p_base_currency char(3), p_fy_start_month int, p_method text, p_owner_name text)
returns uuid language plpgsql security definer set search_path=public as $$
declare o uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  insert into user_profiles(id, full_name) values (auth.uid(), p_owner_name)
    on conflict (id) do update set full_name = excluded.full_name;
  insert into organizations(name,legal_name,country,city,base_currency,fy_start_month,accounting_method)
    values (p_name,p_legal,p_country,p_city,p_base_currency,p_fy_start_month,p_method) returning id into o;
  insert into organization_members values (o, auth.uid(), 'owner');
  insert into accounts(org_id,code,name,type)
  select o, v.c, v.n, v.t::account_type from (values
   ('1000','Cash','asset'),('1100','Bank Accounts','asset'),('1200','Accounts Receivable','asset'),
   ('1300','Prepaid Expenses','asset'),('1400','Inventory','asset'),('1500','Equipment','asset'),
   ('1510','Computer Equipment','asset'),('1590','Accumulated Depreciation','asset'),
   ('2000','Accounts Payable','liability'),('2100','Salaries Payable','liability'),('2200','Taxes Payable','liability'),
   ('2300','Accrued Expenses','liability'),('2500','Loans Payable','liability'),
   ('3000','Owner''s Capital','equity'),('3100','Retained Earnings','equity'),('3200','Owner''s Drawings','equity'),
   ('4000','Service Revenue','revenue'),('4100','SEO Revenue','revenue'),('4200','Digital Marketing Revenue','revenue'),
   ('4300','Recruitment Revenue','revenue'),('4400','Product Revenue','revenue'),('4900','Non-Operating Income','revenue'),
   ('5000','Salaries and Wages','expense'),('5100','Advertising Expenses','expense'),('5200','Software Subscriptions','expense'),
   ('5300','Hosting Expenses','expense'),('5400','Office Rent','expense'),('5500','Internet Expenses','expense'),
   ('5600','Professional Fees','expense'),('5700','Bank Charges','expense'),('5800','Depreciation','expense'),
   ('5900','Miscellaneous Expenses','expense')) as v(c,n,t);
  return o;
end $$;
