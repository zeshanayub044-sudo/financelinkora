-- Department and project dimensions are tenant-scoped, immutable identifiers
-- attached to journal lines, so posted-ledger reports can be filtered safely.
create table public.departments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9._-]{0,39}$'),
  name text not null check (length(trim(name)) between 2 and 200),
  description text check (description is null or length(description)<=1000),
  is_active boolean not null default true,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique(org_id,id),unique(org_id,code)
);
create table public.projects (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9._-]{0,39}$'),
  name text not null check (length(trim(name)) between 2 and 200),
  description text check (description is null or length(description)<=1000),
  is_active boolean not null default true,
  start_date date,
  end_date date,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  check (end_date is null or start_date is null or end_date>=start_date),
  unique(org_id,id),unique(org_id,code)
);

alter table public.journal_lines
  add column department_id uuid,
  add column project_id uuid,
  add constraint journal_lines_department_org_fk foreign key(org_id,department_id)
    references public.departments(org_id,id) on delete restrict,
  add constraint journal_lines_project_org_fk foreign key(org_id,project_id)
    references public.projects(org_id,id) on delete restrict;
create index journal_lines_org_department_idx on public.journal_lines(org_id,department_id) where department_id is not null;
create index journal_lines_org_project_idx on public.journal_lines(org_id,project_id) where project_id is not null;

alter table public.departments enable row level security;
alter table public.projects enable row level security;
create policy departments_read on public.departments for select to authenticated
  using(private.has_role(org_id,array['owner','administrator','accountant','finance_manager','approver','auditor','viewer']::public.member_role[]));
create policy projects_read on public.projects for select to authenticated
  using(private.has_role(org_id,array['owner','administrator','accountant','finance_manager','approver','auditor','viewer']::public.member_role[]));
grant select on public.departments,public.projects to authenticated;
revoke insert,update,delete on public.departments,public.projects from authenticated;

create trigger audit_departments after insert or update or delete on public.departments
  for each row execute function private.audit_row();
create trigger audit_projects after insert or update or delete on public.projects
  for each row execute function private.audit_row();

create or replace function public.create_department(p_org uuid,p_code text,p_name text,p_description text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare actor uuid:=auth.uid();new_id uuid;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to create departments'; end if;
  if nullif(trim(p_code),'') is null or length(trim(p_code))>40 or trim(p_code)!~'^[A-Za-z0-9][A-Za-z0-9._-]*$' then raise exception 'Enter a valid department code'; end if;
  if nullif(trim(p_name),'') is null or length(trim(p_name))>200 or length(trim(coalesce(p_description,'')))>1000 then raise exception 'Enter a valid department name and description'; end if;
  insert into public.departments(org_id,code,name,description,created_by)
    values(p_org,upper(trim(p_code)),trim(p_name),nullif(trim(p_description),''),actor) returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.set_department_active(p_org uuid,p_department uuid,p_active boolean)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to manage departments'; end if;
  if not p_active and exists(select 1 from public.journal_lines l join public.journal_entries e on e.org_id=l.org_id and e.id=l.entry_id
    where l.org_id=p_org and l.department_id=p_department and e.status='draft') then raise exception 'Remove this department from draft journal entries before deactivating it'; end if;
  update public.departments set is_active=p_active where org_id=p_org and id=p_department;
  if not found then raise exception 'Department not found'; end if;
end;
$$;

create or replace function public.create_project(p_org uuid,p_code text,p_name text,p_description text default null,p_start date default null,p_end date default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare actor uuid:=auth.uid();new_id uuid;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to create projects'; end if;
  if nullif(trim(p_code),'') is null or length(trim(p_code))>40 or trim(p_code)!~'^[A-Za-z0-9][A-Za-z0-9._-]*$' then raise exception 'Enter a valid project code'; end if;
  if nullif(trim(p_name),'') is null or length(trim(p_name))>200 or length(trim(coalesce(p_description,'')))>1000 then raise exception 'Enter a valid project name and description'; end if;
  if p_start is not null and p_end is not null and p_end<p_start then raise exception 'Project end date cannot precede its start date'; end if;
  insert into public.projects(org_id,code,name,description,start_date,end_date,created_by)
    values(p_org,upper(trim(p_code)),trim(p_name),nullif(trim(p_description),''),p_start,p_end,actor) returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.set_project_active(p_org uuid,p_project uuid,p_active boolean)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to manage projects'; end if;
  if not p_active and exists(select 1 from public.journal_lines l join public.journal_entries e on e.org_id=l.org_id and e.id=l.entry_id
    where l.org_id=p_org and l.project_id=p_project and e.status='draft') then raise exception 'Remove this project from draft journal entries before deactivating it'; end if;
  update public.projects set is_active=p_active where org_id=p_org and id=p_project;
  if not found then raise exception 'Project not found'; end if;
end;
$$;

-- Active, tenant-consistent dimensions are mandatory when a new allocation is made.
create or replace function public.trg_line_guard()
returns trigger language plpgsql set search_path = ''
as $$
declare entry_state public.entry_status;entry_org uuid;entry_rate numeric(18,8);target_entry uuid;
begin
  if tg_op='DELETE' then target_entry:=old.entry_id; else target_entry:=new.entry_id; end if;
  if tg_op='UPDATE' and (new.entry_id is distinct from old.entry_id or new.org_id is distinct from old.org_id) then raise exception 'A journal line cannot be moved between entries or organizations'; end if;
  select e.status,e.org_id,e.exchange_rate into entry_state,entry_org,entry_rate from public.journal_entries e where e.id=target_entry for update;
  if not found then raise exception 'Journal entry not found'; end if;
  if entry_state<>'draft' then raise exception 'Lines can only be changed on draft entries'; end if;
  if tg_op<>'DELETE' then
    if new.org_id<>entry_org then raise exception 'Line organization must match entry organization'; end if;
    if not exists(select 1 from public.accounts a where a.id=new.account_id and a.org_id=entry_org and a.is_active) then raise exception 'Active account from this organization is required'; end if;
    if new.department_id is not null and not exists(select 1 from public.departments d where d.id=new.department_id and d.org_id=entry_org and d.is_active) then raise exception 'Choose an active department from this organization'; end if;
    if new.project_id is not null and not exists(select 1 from public.projects p where p.id=new.project_id and p.org_id=entry_org and p.is_active) then raise exception 'Choose an active project from this organization'; end if;
    new.exchange_rate:=entry_rate;
    return new;
  end if;
  return old;
end;
$$;

create or replace function public.create_journal_entry_draft(
  p_org uuid,p_entry_date date,p_reference text,p_description text,p_currency char(3),p_exchange_rate numeric,p_entry_kind text,p_lines jsonb
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare actor uuid:=auth.uid();new_entry uuid;item jsonb;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to create journal entries'; end if;
  if nullif(trim(p_description),'') is null then raise exception 'Description is required'; end if;
  if p_exchange_rate is null or p_exchange_rate<=0 or p_exchange_rate::text in ('NaN','Infinity','-Infinity') then raise exception 'Exchange rate must be finite and positive'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<1 then raise exception 'At least one journal line is required'; end if;
  insert into public.journal_entries(org_id,entry_date,reference,description,currency,exchange_rate,created_by,entry_kind)
    values(p_org,p_entry_date,nullif(trim(p_reference),''),trim(p_description),p_currency,p_exchange_rate,actor,coalesce(p_entry_kind,'general')) returning id into new_entry;
  for item in select value from jsonb_array_elements(p_lines) loop
    insert into public.journal_lines(entry_id,org_id,account_id,debit,credit,memo,department_id,project_id)
      values(new_entry,p_org,(item->>'account_id')::uuid,coalesce(nullif(item->>'debit','')::numeric,0),coalesce(nullif(item->>'credit','')::numeric,0),
        nullif(trim(item->>'memo'),''),nullif(item->>'department_id','')::uuid,nullif(item->>'project_id','')::uuid);
  end loop;
  return new_entry;
end;
$$;

create or replace function public.update_journal_entry_draft(p_entry uuid,p_entry_date date,p_reference text,p_description text,p_lines jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare e public.journal_entries%rowtype;actor uuid:=auth.uid();item jsonb;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  select * into e from public.journal_entries where id=p_entry for update;
  if not found then raise exception 'Entry not found'; end if;
  if e.created_by is distinct from actor then raise exception 'Only the draft creator may edit this entry'; end if;
  if not private.has_role(e.org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to edit journal entries'; end if;
  if e.status<>'draft' then raise exception 'Only draft entries can be edited'; end if;
  if nullif(trim(p_description),'') is null then raise exception 'Description is required'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<1 then raise exception 'At least one journal line is required'; end if;
  update public.journal_entries set entry_date=p_entry_date,reference=nullif(trim(p_reference),''),description=trim(p_description) where id=p_entry;
  delete from public.journal_lines where entry_id=p_entry and org_id=e.org_id;
  for item in select value from jsonb_array_elements(p_lines) loop
    insert into public.journal_lines(entry_id,org_id,account_id,debit,credit,memo,department_id,project_id)
      values(p_entry,e.org_id,(item->>'account_id')::uuid,coalesce(nullif(item->>'debit','')::numeric,0),coalesce(nullif(item->>'credit','')::numeric,0),
        nullif(trim(item->>'memo'),''),nullif(item->>'department_id','')::uuid,nullif(item->>'project_id','')::uuid);
  end loop;
end;
$$;

create or replace function public.journal_entry_lines_with_dimensions_exact(p_entry uuid)
returns table(id uuid,account_id uuid,debit text,credit text,memo text,department_id uuid,project_id uuid)
language sql stable security invoker set search_path = ''
as $$
  select l.id,l.account_id,l.debit::text,l.credit::text,l.memo,l.department_id,l.project_id
  from public.journal_lines l where l.entry_id=p_entry order by l.id
$$;

create or replace function public.dimension_activity_exact(p_org uuid,p_from date,p_to date,p_dimension_type text,p_dimension uuid)
returns table(code text,name text,type public.account_type,debit text,credit text,balance text)
language plpgsql stable security invoker set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_from is null or p_to is null or p_from>p_to then raise exception 'Choose a valid reporting date range'; end if;
  if p_dimension_type not in ('department','project') then raise exception 'Choose department or project'; end if;
  if not private.has_role(p_org,array['owner','administrator','accountant','finance_manager','approver','auditor','viewer']::public.member_role[]) then raise exception 'Not authorized to view this organization'; end if;
  if p_dimension_type='department' and not exists(select 1 from public.departments d where d.org_id=p_org and d.id=p_dimension) then raise exception 'Department not found in this organization'; end if;
  if p_dimension_type='project' and not exists(select 1 from public.projects p where p.org_id=p_org and p.id=p_dimension) then raise exception 'Project not found in this organization'; end if;
  return query
    select a.code,a.name,a.type,sum(l.base_debit)::text,sum(l.base_credit)::text,
      (case when a.type in ('asset','expense') then sum(l.base_debit-l.base_credit) else sum(l.base_credit-l.base_debit) end)::text
    from public.journal_lines l join public.journal_entries e on e.org_id=l.org_id and e.id=l.entry_id
      join public.accounts a on a.org_id=l.org_id and a.id=l.account_id
    where l.org_id=p_org and e.status in ('posted','reversed') and e.entry_date between p_from and p_to
      and ((p_dimension_type='department' and l.department_id=p_dimension) or (p_dimension_type='project' and l.project_id=p_dimension))
    group by a.id,a.code,a.name,a.type order by a.code;
end;
$$;

revoke all on function public.create_department(uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.set_department_active(uuid,uuid,boolean) from public,anon,authenticated;
revoke all on function public.create_project(uuid,text,text,text,date,date) from public,anon,authenticated;
revoke all on function public.set_project_active(uuid,uuid,boolean) from public,anon,authenticated;
revoke all on function public.create_journal_entry_draft(uuid,date,text,text,char,numeric,text,jsonb) from public,anon,authenticated;
revoke all on function public.update_journal_entry_draft(uuid,date,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.journal_entry_lines_with_dimensions_exact(uuid) from public,anon,authenticated;
revoke all on function public.dimension_activity_exact(uuid,date,date,text,uuid) from public,anon,authenticated;
grant execute on function public.create_department(uuid,text,text,text) to authenticated;
grant execute on function public.set_department_active(uuid,uuid,boolean) to authenticated;
grant execute on function public.create_project(uuid,text,text,text,date,date) to authenticated;
grant execute on function public.set_project_active(uuid,uuid,boolean) to authenticated;
grant execute on function public.create_journal_entry_draft(uuid,date,text,text,char,numeric,text,jsonb) to authenticated;
grant execute on function public.update_journal_entry_draft(uuid,date,text,text,jsonb) to authenticated;
grant execute on function public.journal_entry_lines_with_dimensions_exact(uuid) to authenticated;
grant execute on function public.dimension_activity_exact(uuid,date,date,text,uuid) to authenticated;
