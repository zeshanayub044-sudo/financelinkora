-- Payroll records and runs are tenant-scoped. Pay amounts are manually entered;
-- this migration does not infer country tax, contributions, or employment law.
alter table public.journal_entries drop constraint if exists journal_entries_entry_kind_check;
alter table public.journal_entries add constraint journal_entries_entry_kind_check check (entry_kind in (
  'general','opening_balance','income','expense','payment','bank_transfer','reversal','closing',
  'sales_invoice','purchase_bill','customer_payment','supplier_payment','depreciation','payroll'
));

create table public.payroll_employees (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  employee_code text not null check (employee_code ~ '^[A-Z0-9][A-Z0-9._-]{0,39}$'),
  full_name text not null check (length(trim(full_name)) between 2 and 200),
  email text check (email is null or length(email)<=254),
  department_id uuid,
  start_date date not null,
  end_date date,
  is_active boolean not null default true,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  check (end_date is null or end_date>=start_date),
  unique(org_id,id),unique(org_id,employee_code),
  foreign key(org_id,department_id) references public.departments(org_id,id) on delete restrict
);

create table public.payroll_components (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9._-]{0,39}$'),
  name text not null check (length(trim(name)) between 2 and 200),
  component_type text not null check (component_type in ('earning','deduction')),
  account_id uuid not null,
  is_active boolean not null default true,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique(org_id,id),unique(org_id,code),
  foreign key(org_id,account_id) references public.accounts(org_id,id) on delete restrict
);

create table public.payroll_runs (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  reference text not null check (length(trim(reference)) between 1 and 80),
  period_start date not null,
  period_end date not null,
  payable_account_id uuid not null,
  status text not null default 'draft' check (status in ('draft','in_review','posted','rejected','reversed')),
  journal_entry_id uuid,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique(org_id,id),unique(org_id,reference),unique(org_id,journal_entry_id),
  foreign key(org_id,payable_account_id) references public.accounts(org_id,id) on delete restrict,
  foreign key(org_id,journal_entry_id) references public.journal_entries(org_id,id) on delete restrict,
  check (period_end>=period_start)
);

create table public.payroll_run_lines (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  run_id uuid not null,
  employee_id uuid not null,
  employee_code text not null,
  employee_name text not null,
  component_id uuid not null,
  component_code text not null,
  component_name text not null,
  component_type text not null check (component_type in ('earning','deduction')),
  account_id uuid not null,
  amount numeric(20,4) not null check (amount>0 and amount::text not in ('NaN','Infinity','-Infinity')),
  created_at timestamptz not null default now(),
  unique(org_id,id),unique(org_id,run_id,employee_id,component_id),
  foreign key(org_id,run_id) references public.payroll_runs(org_id,id) on delete cascade,
  foreign key(org_id,employee_id) references public.payroll_employees(org_id,id) on delete restrict,
  foreign key(org_id,component_id) references public.payroll_components(org_id,id) on delete restrict,
  foreign key(org_id,account_id) references public.accounts(org_id,id) on delete restrict
);

create index payroll_employees_org_active_idx on public.payroll_employees(org_id,is_active,employee_code);
create index payroll_components_org_active_idx on public.payroll_components(org_id,is_active,component_type,code);
create index payroll_runs_org_period_idx on public.payroll_runs(org_id,period_start desc,status);
create index payroll_run_lines_run_idx on public.payroll_run_lines(org_id,run_id,employee_code,component_code);

alter table public.payroll_employees enable row level security;
alter table public.payroll_components enable row level security;
alter table public.payroll_runs enable row level security;
alter table public.payroll_run_lines enable row level security;
create policy payroll_employees_read on public.payroll_employees for select to authenticated
  using(private.has_role(org_id,array['owner','administrator','finance_manager','accountant','approver','auditor']::public.member_role[]));
create policy payroll_components_read on public.payroll_components for select to authenticated
  using(private.has_role(org_id,array['owner','administrator','finance_manager','accountant','approver','auditor']::public.member_role[]));
create policy payroll_runs_read on public.payroll_runs for select to authenticated
  using(private.has_role(org_id,array['owner','administrator','finance_manager','accountant','approver','auditor']::public.member_role[]));
create policy payroll_run_lines_read on public.payroll_run_lines for select to authenticated
  using(private.has_role(org_id,array['owner','administrator','finance_manager','accountant','approver','auditor']::public.member_role[]));
grant select on public.payroll_employees,public.payroll_components,public.payroll_runs,public.payroll_run_lines to authenticated;
revoke all on public.payroll_employees,public.payroll_components,public.payroll_runs,public.payroll_run_lines from anon;
revoke insert,update,delete on public.payroll_employees,public.payroll_components,public.payroll_runs,public.payroll_run_lines from authenticated;

create trigger audit_payroll_employees after insert or update or delete on public.payroll_employees for each row execute function private.audit_row();
create trigger audit_payroll_components after insert or update or delete on public.payroll_components for each row execute function private.audit_row();
create trigger audit_payroll_runs after insert or update or delete on public.payroll_runs for each row execute function private.audit_row();
create trigger audit_payroll_run_lines after insert or update or delete on public.payroll_run_lines for each row execute function private.audit_row();

create or replace function public.create_payroll_employee(
  p_org uuid,p_code text,p_name text,p_start date,p_email text default null,p_department uuid default null
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare actor uuid:=auth.uid();new_id uuid;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','finance_manager','accountant']::public.member_role[]) then raise exception 'Not authorized to manage payroll employees'; end if;
  if nullif(trim(p_code),'') is null or length(trim(p_code))>40 or trim(p_code)!~'^[A-Za-z0-9][A-Za-z0-9._-]*$' then raise exception 'Enter a valid employee code'; end if;
  if nullif(trim(p_name),'') is null or length(trim(p_name))>200 then raise exception 'Enter an employee name'; end if;
  if p_start is null or length(coalesce(p_email,''))>254 then raise exception 'Enter valid employee contact and start-date details'; end if;
  if p_department is not null and not exists(select 1 from public.departments d where d.org_id=p_org and d.id=p_department and d.is_active) then raise exception 'Choose an active department in this organization'; end if;
  insert into public.payroll_employees(org_id,employee_code,full_name,email,department_id,start_date,created_by)
    values(p_org,upper(trim(p_code)),trim(p_name),nullif(trim(p_email),''),p_department,p_start,actor) returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.set_payroll_employee_active(p_org uuid,p_employee uuid,p_active boolean)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','finance_manager','accountant']::public.member_role[]) then raise exception 'Not authorized to manage payroll employees'; end if;
  update public.payroll_employees set is_active=p_active where org_id=p_org and id=p_employee;
  if not found then raise exception 'Employee not found in this organization'; end if;
end;
$$;

create or replace function public.create_payroll_component(p_org uuid,p_code text,p_name text,p_type text,p_account uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare actor uuid:=auth.uid();new_id uuid;expected_type public.account_type;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','finance_manager','accountant']::public.member_role[]) then raise exception 'Not authorized to manage payroll components'; end if;
  if nullif(trim(p_code),'') is null or length(trim(p_code))>40 or trim(p_code)!~'^[A-Za-z0-9][A-Za-z0-9._-]*$' then raise exception 'Enter a valid payroll component code'; end if;
  if nullif(trim(p_name),'') is null or length(trim(p_name))>200 then raise exception 'Enter a payroll component name'; end if;
  if p_type not in ('earning','deduction') then raise exception 'Choose an earning or deduction component'; end if;
  expected_type:=case when p_type='earning' then 'expense'::public.account_type else 'liability'::public.account_type end;
  if not exists(select 1 from public.accounts a where a.org_id=p_org and a.id=p_account and a.is_active and a.type=expected_type and a.reporting_class is null) then raise exception 'Choose an active unclassified expense or liability account of the matching type'; end if;
  insert into public.payroll_components(org_id,code,name,component_type,account_id,created_by) values(p_org,upper(trim(p_code)),trim(p_name),p_type,p_account,actor) returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.set_payroll_component_active(p_org uuid,p_component uuid,p_active boolean)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','finance_manager','accountant']::public.member_role[]) then raise exception 'Not authorized to manage payroll components'; end if;
  update public.payroll_components set is_active=p_active where org_id=p_org and id=p_component;
  if not found then raise exception 'Payroll component not found in this organization'; end if;
end;
$$;

create or replace function public.create_payroll_run_draft(
  p_org uuid,p_reference text,p_period_start date,p_period_end date,p_payable_account uuid,p_lines jsonb
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare actor uuid:=auth.uid();new_run_id uuid;item jsonb;employee_id uuid;component_id uuid;amount numeric;run_employee public.payroll_employees%rowtype;run_component public.payroll_components%rowtype;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','finance_manager','accountant']::public.member_role[]) then raise exception 'Not authorized to create payroll runs'; end if;
  if nullif(trim(p_reference),'') is null or length(trim(p_reference))>80 then raise exception 'Enter a payroll reference'; end if;
  if p_period_start is null or p_period_end is null or p_period_start<>date_trunc('month',p_period_start)::date or p_period_end<>(date_trunc('month',p_period_start)+interval '1 month - 1 day')::date then raise exception 'Payroll runs must cover one complete calendar month'; end if;
  perform private.assert_open_period(p_org,p_period_end);
  if not exists(select 1 from public.accounts a where a.org_id=p_org and a.id=p_payable_account and a.is_active and a.type='liability' and a.reporting_class is null) then raise exception 'Choose an active unclassified payroll payable account'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<1 or jsonb_array_length(p_lines)>2000 then raise exception 'A payroll run needs between 1 and 2000 component lines'; end if;
  insert into public.payroll_runs(org_id,reference,period_start,period_end,payable_account_id,created_by)
    values(p_org,trim(p_reference),p_period_start,p_period_end,p_payable_account,actor) returning id into new_run_id;
  for item in select value from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(item)<>'object' then raise exception 'Payroll lines must be objects'; end if;
    employee_id:=(item->>'employee_id')::uuid;component_id:=(item->>'component_id')::uuid;amount:=(item->>'amount')::numeric;
    if amount is null or amount<=0 or amount::text in ('NaN','Infinity','-Infinity') or amount<>round(amount,4) then raise exception 'Payroll amounts must be finite, positive, and use at most four decimal places'; end if;
    select * into run_employee from public.payroll_employees where org_id=p_org and id=employee_id and is_active;
    if not found or p_period_end<run_employee.start_date or (run_employee.end_date is not null and p_period_start>run_employee.end_date) then raise exception 'Choose an active employee employed during this payroll period'; end if;
    select * into run_component from public.payroll_components where org_id=p_org and id=component_id and is_active;
    if not found then raise exception 'Choose an active payroll component in this organization'; end if;
    insert into public.payroll_run_lines(org_id,run_id,employee_id,employee_code,employee_name,component_id,component_code,component_name,component_type,account_id,amount)
      values(p_org,new_run_id,run_employee.id,run_employee.employee_code,run_employee.full_name,run_component.id,run_component.code,run_component.name,run_component.component_type,run_component.account_id,amount);
  end loop;
  if not exists(select 1 from public.payroll_run_lines l where l.org_id=p_org and l.run_id=new_run_id and l.component_type='earning') then raise exception 'Payroll run needs at least one earning component'; end if;
  if exists(select l.employee_id from public.payroll_run_lines l where l.org_id=p_org and l.run_id=new_run_id group by l.employee_id having coalesce(sum(l.amount) filter(where l.component_type='deduction'),0)>coalesce(sum(l.amount) filter(where l.component_type='earning'),0)) then raise exception 'Employee deductions cannot exceed that employee earnings'; end if;
  return new_run_id;
end;
$$;

create or replace function private.payroll_journal_lines(p_run uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare r public.payroll_runs%rowtype;gross numeric(30,4);deductions numeric(30,4);lines jsonb;
begin
  select * into r from public.payroll_runs where id=p_run;
  if not found then raise exception 'Payroll run not found'; end if;
  if r.status not in ('draft','in_review','posted') then raise exception 'Payroll run is not eligible for journal submission'; end if;
  if r.status in ('draft','in_review') and not exists(select 1 from public.accounts a where a.org_id=r.org_id and a.id=r.payable_account_id and a.is_active and a.type='liability' and a.reporting_class is null) then raise exception 'Payroll payable account is no longer active'; end if;
  if r.status in ('draft','in_review') and exists(select 1 from public.payroll_run_lines l join public.accounts a on a.org_id=l.org_id and a.id=l.account_id where l.org_id=r.org_id and l.run_id=r.id and (not a.is_active or a.reporting_class is not null or (l.component_type='earning' and a.type<>'expense') or (l.component_type='deduction' and a.type<>'liability'))) then raise exception 'Payroll component accounts are no longer active or valid'; end if;
  select coalesce(sum(amount) filter(where component_type='earning'),0),coalesce(sum(amount) filter(where component_type='deduction'),0)
    into gross,deductions from public.payroll_run_lines where org_id=r.org_id and run_id=r.id;
  if gross<=0 or deductions>gross then raise exception 'Payroll run totals are invalid'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('account_id',entry.account_id,'debit',entry.debit::text,'credit',entry.credit::text,'memo',entry.memo) order by entry.sort_key,entry.account_id),'[]'::jsonb)
    into lines from (
      select l.account_id,sum(l.amount) debit,0::numeric credit,'Payroll earnings'::text memo,1 sort_key
      from public.payroll_run_lines l where l.org_id=r.org_id and l.run_id=r.id and l.component_type='earning' group by l.account_id
      union all
      select l.account_id,0::numeric,sum(l.amount),'Payroll deductions · '||min(l.component_name),2
      from public.payroll_run_lines l where l.org_id=r.org_id and l.run_id=r.id and l.component_type='deduction' group by l.account_id
      union all
      select r.payable_account_id,0::numeric,gross-deductions,'Net payroll payable',3 where gross>deductions
    ) entry;
  return lines;
end;
$$;
revoke all on function private.payroll_journal_lines(uuid) from public,anon,authenticated;

create or replace function public.update_payroll_run_draft(p_run uuid,p_lines jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare r public.payroll_runs%rowtype;actor uuid:=auth.uid();item jsonb;employee_id uuid;component_id uuid;amount numeric;emp public.payroll_employees%rowtype;comp public.payroll_components%rowtype;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  select * into r from public.payroll_runs where id=p_run for update;
  if not found or r.created_by<>actor or not private.has_role(r.org_id,array['owner','administrator','finance_manager','accountant']::public.member_role[]) then raise exception 'Not authorized to edit this payroll run'; end if;
  if r.status<>'draft' or r.journal_entry_id is null or not exists(select 1 from public.journal_entries e where e.org_id=r.org_id and e.id=r.journal_entry_id and e.status='draft' and e.entry_kind='payroll') then raise exception 'Only a rejected payroll draft may be edited'; end if;
  perform private.assert_open_period(r.org_id,r.period_end);
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<1 or jsonb_array_length(p_lines)>2000 then raise exception 'A payroll run needs between 1 and 2000 component lines'; end if;
  delete from public.payroll_run_lines where org_id=r.org_id and run_id=r.id;
  for item in select value from jsonb_array_elements(p_lines) loop
    employee_id:=(item->>'employee_id')::uuid;component_id:=(item->>'component_id')::uuid;amount:=(item->>'amount')::numeric;
    if amount is null or amount<=0 or amount::text in ('NaN','Infinity','-Infinity') or amount<>round(amount,4) then raise exception 'Payroll amounts must be finite, positive, and use at most four decimal places'; end if;
    select * into emp from public.payroll_employees where org_id=r.org_id and id=employee_id and is_active;
    if not found or r.period_end<emp.start_date or (emp.end_date is not null and r.period_start>emp.end_date) then raise exception 'Choose an active employee employed during this payroll period'; end if;
    select * into comp from public.payroll_components where org_id=r.org_id and id=component_id and is_active;
    if not found then raise exception 'Choose an active payroll component in this organization'; end if;
    insert into public.payroll_run_lines(org_id,run_id,employee_id,employee_code,employee_name,component_id,component_code,component_name,component_type,account_id,amount)
      values(r.org_id,r.id,emp.id,emp.employee_code,emp.full_name,comp.id,comp.code,comp.name,comp.component_type,comp.account_id,amount);
  end loop;
  if not exists(select 1 from public.payroll_run_lines l where l.org_id=r.org_id and l.run_id=r.id and l.component_type='earning') then raise exception 'Payroll run needs at least one earning component'; end if;
  if exists(select l.employee_id from public.payroll_run_lines l where l.org_id=r.org_id and l.run_id=r.id group by l.employee_id having coalesce(sum(l.amount) filter(where l.component_type='deduction'),0)>coalesce(sum(l.amount) filter(where l.component_type='earning'),0)) then raise exception 'Employee deductions cannot exceed that employee earnings'; end if;
  perform public.update_journal_entry_draft(r.journal_entry_id,r.period_end,r.reference,'Payroll run '||r.reference,private.payroll_journal_lines(r.id));
end;
$$;

create or replace function public.submit_payroll_run(p_run uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare r public.payroll_runs%rowtype;actor uuid:=auth.uid();journal_id uuid;lines jsonb;currency char(3);
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  select * into r from public.payroll_runs where id=p_run for update;
  if not found then raise exception 'Payroll run not found'; end if;
  if r.created_by<>actor then raise exception 'Only the payroll run creator may submit it'; end if;
  if not private.has_role(r.org_id,array['owner','administrator','finance_manager','accountant']::public.member_role[]) then raise exception 'Not authorized to submit payroll'; end if;
  if r.status<>'draft' then raise exception 'Only a draft payroll run may be submitted'; end if;
  perform private.assert_open_period(r.org_id,r.period_end);
  lines:=private.payroll_journal_lines(r.id);
  select base_currency into currency from public.organizations where id=r.org_id;
  if r.journal_entry_id is null then
    journal_id:=public.create_journal_entry_draft(r.org_id,r.period_end,r.reference,'Payroll run '||r.reference,currency,1,'payroll',lines);
    update public.payroll_runs set journal_entry_id=journal_id,status='in_review' where id=r.id;
  else
    journal_id:=r.journal_entry_id;
    perform public.update_journal_entry_draft(journal_id,r.period_end,r.reference,'Payroll run '||r.reference,lines);
    update public.payroll_runs set status='in_review' where id=r.id;
  end if;
  perform public.submit_journal_entry(journal_id);
  update public.journal_entries set rejection_reason=null,rejected_at=null,rejected_by=null where id=journal_id and rejection_reason is not null;
  return journal_id;
end;
$$;

create or replace function private.guard_payroll_entry()
returns trigger language plpgsql set search_path = ''
as $$
declare r public.payroll_runs%rowtype;expected jsonb;
begin
  if new.entry_kind<>'payroll' or new.status is not distinct from old.status then return new; end if;
  select * into r from public.payroll_runs where org_id=new.org_id and journal_entry_id=new.id for update;
  if not found then raise exception 'Payroll journal entry must link to a payroll run'; end if;
  if r.created_by is distinct from new.created_by or r.org_id is distinct from new.org_id then raise exception 'Payroll run does not match the journal maker or organization'; end if;
  expected:=private.payroll_journal_lines(r.id);
  if exists(
    (select l.account_id,l.debit,l.credit from public.journal_lines l where l.org_id=new.org_id and l.entry_id=new.id
      except all select (line->>'account_id')::uuid,coalesce((line->>'debit')::numeric,0),coalesce((line->>'credit')::numeric,0) from jsonb_array_elements(expected) as x(line))
    union all
    (select (line->>'account_id')::uuid,coalesce((line->>'debit')::numeric,0),coalesce((line->>'credit')::numeric,0) from jsonb_array_elements(expected) as x(line)
      except all select l.account_id,l.debit,l.credit from public.journal_lines l where l.org_id=new.org_id and l.entry_id=new.id)
  ) then raise exception 'Payroll journal lines differ from the approved payroll run'; end if;
  return new;
end;
$$;
revoke all on function private.guard_payroll_entry() from public,anon,authenticated;
create trigger guard_payroll_entry before update of status on public.journal_entries for each row execute function private.guard_payroll_entry();

create or replace function private.sync_payroll_run_status()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if old.status is distinct from new.status and new.entry_kind='payroll' then
    if new.status='posted' then update public.payroll_runs set status='posted' where org_id=new.org_id and journal_entry_id=new.id;
    elsif new.status='reversed' then update public.payroll_runs set status='reversed' where org_id=new.org_id and journal_entry_id=new.id;
    elsif new.status='draft' and new.rejection_reason is not null then update public.payroll_runs set status='draft' where org_id=new.org_id and journal_entry_id=new.id;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.sync_payroll_run_status() from public,anon,authenticated;
create trigger sync_payroll_run_status after update of status on public.journal_entries for each row execute function private.sync_payroll_run_status();

revoke all on function public.create_payroll_employee(uuid,text,text,date,text,uuid) from public,anon,authenticated;
revoke all on function public.set_payroll_employee_active(uuid,uuid,boolean) from public,anon,authenticated;
revoke all on function public.create_payroll_component(uuid,text,text,text,uuid) from public,anon,authenticated;
revoke all on function public.set_payroll_component_active(uuid,uuid,boolean) from public,anon,authenticated;
revoke all on function public.create_payroll_run_draft(uuid,text,date,date,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.submit_payroll_run(uuid) from public,anon,authenticated;
revoke all on function public.update_payroll_run_draft(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.create_payroll_employee(uuid,text,text,date,text,uuid) to authenticated;
grant execute on function public.set_payroll_employee_active(uuid,uuid,boolean) to authenticated;
grant execute on function public.create_payroll_component(uuid,text,text,text,uuid) to authenticated;
grant execute on function public.set_payroll_component_active(uuid,uuid,boolean) to authenticated;
grant execute on function public.create_payroll_run_draft(uuid,text,date,date,uuid,jsonb) to authenticated;
grant execute on function public.submit_payroll_run(uuid) to authenticated;
grant execute on function public.update_payroll_run_draft(uuid,jsonb) to authenticated;
