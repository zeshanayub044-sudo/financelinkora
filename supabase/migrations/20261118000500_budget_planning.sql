-- Budget planning stays separate from journal posting. Actuals always come from posted ledger lines.
create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (length(trim(name)) between 2 and 150),
  start_date date not null,
  end_date date not null,
  status text not null default 'draft' check (status in ('draft','approved')),
  created_by uuid not null default auth.uid() references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date>=start_date),
  check (extract(day from start_date)=1),
  check (end_date=(date_trunc('month',end_date)+interval '1 month'-interval '1 day')::date),
  check ((status='approved')=(approved_by is not null and approved_at is not null)),
  unique (org_id,id)
);
create table public.budget_lines (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  budget_id uuid not null,
  account_id uuid not null,
  period_start date not null check (extract(day from period_start)=1),
  amount numeric(20,4) not null check (amount>0),
  created_at timestamptz not null default now(),
  check (amount::text not in ('NaN','Infinity','-Infinity')),
  foreign key (org_id,budget_id) references public.budgets(org_id,id) on delete cascade,
  foreign key (org_id,account_id) references public.accounts(org_id,id) on delete restrict,
  unique (org_id,budget_id,account_id,period_start)
);
create index budget_lines_org_period_idx on public.budget_lines(org_id,period_start,budget_id);
alter table public.budgets enable row level security;
alter table public.budget_lines enable row level security;
create policy budgets_read on public.budgets for select to authenticated
  using (private.has_role(org_id,array['owner','administrator','accountant','finance_manager','approver','auditor','viewer']::public.member_role[]));
create policy budget_lines_read on public.budget_lines for select to authenticated
  using (private.has_role(org_id,array['owner','administrator','accountant','finance_manager','approver','auditor','viewer']::public.member_role[]));
grant select on public.budgets,public.budget_lines to authenticated;
revoke all on public.budgets,public.budget_lines from anon;
create trigger audit_budgets after insert or update or delete on public.budgets
  for each row execute function private.audit_row();
create trigger audit_budget_lines after insert or update or delete on public.budget_lines
  for each row execute function private.audit_row();

create or replace function private.insert_budget_lines(p_org uuid,p_budget uuid,p_start date,p_end date,p_lines jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare item jsonb;account uuid;line_month date;amount_value numeric;
begin
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<1 then
    raise exception 'Add at least one monthly budget line';
  end if;
  if jsonb_array_length(p_lines)>2000 then raise exception 'A budget may contain at most 2000 lines'; end if;
  for item in select value from jsonb_array_elements(p_lines) loop
    account:=(item->>'account_id')::uuid;
    line_month:=(item->>'period_start')::date;
    amount_value:=(item->>'amount')::numeric;
    if extract(day from line_month)<>1 or line_month<p_start or line_month>p_end then
      raise exception 'Budget line must start on a month within the budget date range';
    end if;
    if amount_value<=0 or amount_value::text in ('NaN','Infinity','-Infinity') then
      raise exception 'Budget amounts must be finite and greater than zero';
    end if;
    if not exists(select 1 from public.accounts a where a.org_id=p_org and a.id=account
      and a.is_active and a.type in ('revenue','expense')) then
      raise exception 'Budget lines require an active revenue or expense account in this organization';
    end if;
    insert into public.budget_lines(org_id,budget_id,account_id,period_start,amount)
      values(p_org,p_budget,account,line_month,amount_value);
  end loop;
end;
$$;
revoke all on function private.insert_budget_lines(uuid,uuid,date,date,jsonb) from public,anon,authenticated;

create or replace function public.create_budget_draft(p_org uuid,p_name text,p_start date,p_end date,p_lines jsonb)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare actor uuid:=auth.uid();new_budget uuid;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then
    raise exception 'Not authorized to create budgets';
  end if;
  if nullif(trim(p_name),'') is null or length(trim(p_name))>150 then raise exception 'Enter a budget name'; end if;
  if p_start is null or p_end is null or p_end<p_start then raise exception 'Invalid budget date range'; end if;
  if extract(day from p_start)<>1 or p_end<>(date_trunc('month',p_end)+interval '1 month'-interval '1 day')::date then
    raise exception 'Budgets must start on a month boundary and end on a month boundary';
  end if;
  insert into public.budgets(org_id,name,start_date,end_date,created_by)
    values(p_org,trim(p_name),p_start,p_end,actor) returning id into new_budget;
  perform private.insert_budget_lines(p_org,new_budget,p_start,p_end,p_lines);
  return new_budget;
end;
$$;

create or replace function public.update_budget_draft(p_budget uuid,p_name text,p_start date,p_end date,p_lines jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare b public.budgets%rowtype;actor uuid:=auth.uid();
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  select * into b from public.budgets where id=p_budget for update;
  if not found then raise exception 'Budget not found'; end if;
  if b.created_by is distinct from actor then raise exception 'Only the draft creator may edit this budget'; end if;
  if not private.has_role(b.org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then
    raise exception 'Not authorized to edit budgets';
  end if;
  if b.status<>'draft' then raise exception 'Only draft budgets can be edited'; end if;
  if nullif(trim(p_name),'') is null or length(trim(p_name))>150 then raise exception 'Enter a budget name'; end if;
  if p_start is null or p_end is null or p_end<p_start then raise exception 'Invalid budget date range'; end if;
  if extract(day from p_start)<>1 or p_end<>(date_trunc('month',p_end)+interval '1 month'-interval '1 day')::date then
    raise exception 'Budgets must start on a month boundary and end on a month boundary';
  end if;
  delete from public.budget_lines where org_id=b.org_id and budget_id=b.id;
  update public.budgets set name=trim(p_name),start_date=p_start,end_date=p_end,updated_at=now() where id=b.id;
  perform private.insert_budget_lines(b.org_id,b.id,p_start,p_end,p_lines);
end;
$$;

create or replace function public.approve_budget(p_budget uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare b public.budgets%rowtype;actor uuid:=auth.uid();
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  select * into b from public.budgets where id=p_budget for update;
  if not found then raise exception 'Budget not found'; end if;
  if not private.has_role(b.org_id,array['owner','finance_manager','approver']::public.member_role[]) then
    raise exception 'Not authorized to approve budgets';
  end if;
  if b.created_by=actor then raise exception 'Maker-checker: the creator cannot approve their own budget'; end if;
  if b.status<>'draft' then raise exception 'Only draft budgets can be approved'; end if;
  update public.budgets set status='approved',approved_by=actor,approved_at=now(),updated_at=now() where id=b.id;
end;
$$;

create or replace function public.budget_variance_exact(p_budget uuid)
returns table(period_start date,account_id uuid,code text,name text,type public.account_type,
  budget text,actual text,actual_minus_budget text)
language sql stable security invoker set search_path = ''
as $$
  select bl.period_start,a.id,a.code,a.name,a.type,bl.amount::text,
    coalesce(sum(case when a.type='revenue' then l.base_credit-l.base_debit else l.base_debit-l.base_credit end),0)::text,
    (coalesce(sum(case when a.type='revenue' then l.base_credit-l.base_debit else l.base_debit-l.base_credit end),0)-bl.amount)::text
  from public.budget_lines bl
  join public.budgets b on b.org_id=bl.org_id and b.id=bl.budget_id
  join public.accounts a on a.org_id=bl.org_id and a.id=bl.account_id
  left join public.journal_entries e on e.org_id=bl.org_id and e.status in ('posted','reversed')
    and e.entry_date>=bl.period_start and e.entry_date<(bl.period_start+interval '1 month')::date
  left join public.journal_lines l on l.org_id=bl.org_id and l.entry_id=e.id and l.account_id=bl.account_id
  where b.id=p_budget
  group by bl.period_start,a.id,a.code,a.name,a.type,bl.amount
  order by bl.period_start,a.code;
$$;

revoke all on function public.create_budget_draft(uuid,text,date,date,jsonb) from public,anon,authenticated;
revoke all on function public.update_budget_draft(uuid,text,date,date,jsonb) from public,anon,authenticated;
revoke all on function public.approve_budget(uuid) from public,anon,authenticated;
revoke all on function public.budget_variance_exact(uuid) from public,anon,authenticated;
grant execute on function public.create_budget_draft(uuid,text,date,date,jsonb) to authenticated;
grant execute on function public.update_budget_draft(uuid,text,date,date,jsonb) to authenticated;
grant execute on function public.approve_budget(uuid) to authenticated;
grant execute on function public.budget_variance_exact(uuid) to authenticated;
