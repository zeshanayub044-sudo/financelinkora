-- Fixed assets use the ordinary journal approval/post/reversal process.
-- Acquisitions link to an already-posted asset debit; straight-line depreciation
-- creates one journal draft per period and is checked again before transition.
alter table public.journal_entries
  drop constraint if exists journal_entries_entry_kind_check,
  add constraint journal_entries_entry_kind_check check (entry_kind in (
    'general','opening_balance','income','expense','payment','bank_transfer','reversal','closing',
    'sales_invoice','purchase_bill','customer_payment','supplier_payment','depreciation'
  ));

alter table public.accounts drop constraint if exists accounts_reporting_class_check;
alter table public.accounts add constraint accounts_reporting_class_check check (
  reporting_class is null
  or (reporting_class in ('cash','bank','receivable','accumulated_depreciation') and type='asset')
  or (reporting_class='payable' and type='liability')
);
-- The established starter chart already has the accumulated-depreciation account.
-- Classify it consistently for current organizations and future org setup calls.
update public.accounts set reporting_class='accumulated_depreciation'
where code='1590' and type='asset' and reporting_class is null;
create or replace function private.classify_starter_contra_asset()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.code='1590' and new.type='asset' and new.reporting_class is null then
    new.reporting_class:='accumulated_depreciation';
  end if;
  return new;
end;
$$;
revoke all on function private.classify_starter_contra_asset() from public,anon,authenticated;
create trigger classify_starter_contra_asset before insert on public.accounts
  for each row execute function private.classify_starter_contra_asset();

create or replace function private.guard_contra_asset_classification()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if old.reporting_class is distinct from new.reporting_class and (
    exists(select 1 from public.fixed_assets fa where fa.org_id=old.org_id and old.id in (fa.asset_account_id,fa.accumulated_depreciation_account_id,fa.depreciation_expense_account_id))
    or ((old.reporting_class='accumulated_depreciation' or new.reporting_class='accumulated_depreciation')
      and exists(select 1 from public.journal_lines l join public.journal_entries e on e.org_id=l.org_id and e.id=l.entry_id
        where l.org_id=old.org_id and l.account_id=old.id and e.status in ('posted','reversed')))
  ) then
    raise exception 'Fixed-asset and contra-asset account classification is locked after use';
  end if;
  return new;
end;
$$;
revoke all on function private.guard_contra_asset_classification() from public,anon,authenticated;
create trigger guard_contra_asset_classification before update of reporting_class on public.accounts
  for each row execute function private.guard_contra_asset_classification();

create or replace view public.ledger with (security_invoker=true) as
select l.org_id,a.id as account_id,a.code,a.name as account_name,e.id as entry_id,e.entry_no,
  e.entry_date,e.description,l.memo,l.base_debit as debit,l.base_credit as credit,
  sum(case when a.normal_balance='debit' and a.reporting_class is distinct from 'accumulated_depreciation'
        then l.base_debit-l.base_credit else l.base_credit-l.base_debit end)
    over(partition by l.account_id order by e.entry_date,e.entry_no,l.id) as running_balance,
  e.currency,e.exchange_rate,l.debit as transaction_debit,l.credit as transaction_credit
from public.journal_lines l
join public.journal_entries e on e.id=l.entry_id and e.org_id=l.org_id
join public.accounts a on a.id=l.account_id and a.org_id=l.org_id
where e.status in ('posted','reversed');

create table public.fixed_assets (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  asset_code text not null check (length(trim(asset_code)) between 1 and 40),
  name text not null check (length(trim(name)) between 2 and 200),
  description text check (description is null or length(description)<=1000),
  acquisition_date date not null,
  in_service_date date not null,
  cost numeric(20,4) not null check (cost>0 and cost::text not in ('NaN','Infinity','-Infinity')),
  residual_value numeric(20,4) not null default 0 check (residual_value>=0 and residual_value::text not in ('NaN','Infinity','-Infinity')),
  useful_life_months integer not null check (useful_life_months between 1 and 1200),
  asset_account_id uuid not null,
  accumulated_depreciation_account_id uuid not null,
  depreciation_expense_account_id uuid not null,
  acquisition_entry_id uuid not null,
  status text not null default 'active' check (status in ('active','disposed')),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  check (in_service_date>=acquisition_date),
  check (residual_value<=cost),
  unique (org_id,id),
  unique (org_id,asset_code),
  foreign key (org_id,asset_account_id) references public.accounts(org_id,id) on delete restrict,
  foreign key (org_id,accumulated_depreciation_account_id) references public.accounts(org_id,id) on delete restrict,
  foreign key (org_id,depreciation_expense_account_id) references public.accounts(org_id,id) on delete restrict,
  foreign key (org_id,acquisition_entry_id) references public.journal_entries(org_id,id) on delete restrict
);

create table public.asset_depreciation_runs (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  status text not null default 'draft' check (status in ('draft','submitted','posted','reversed')),
  journal_entry_id uuid,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  check (period_end>=period_start),
  unique (org_id,id),
  unique (org_id,journal_entry_id),
  foreign key (org_id,journal_entry_id) references public.journal_entries(org_id,id) on delete restrict
);

create table public.asset_depreciation_lines (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  run_id uuid not null,
  asset_id uuid not null,
  period_end date not null,
  amount numeric(20,4) not null check (amount>0 and amount::text not in ('NaN','Infinity','-Infinity')),
  status text not null default 'draft' check (status in ('draft','submitted','posted','reversed')),
  created_at timestamptz not null default now(),
  unique (org_id,id),
  unique (org_id,run_id,asset_id),
  foreign key (org_id,run_id) references public.asset_depreciation_runs(org_id,id) on delete restrict,
  foreign key (org_id,asset_id) references public.fixed_assets(org_id,id) on delete restrict
);
create unique index asset_depreciation_active_period_idx on public.asset_depreciation_lines(org_id,asset_id,period_end) where status<>'reversed';
create index fixed_assets_org_status_idx on public.fixed_assets(org_id,status,asset_code);
create index asset_depreciation_runs_period_idx on public.asset_depreciation_runs(org_id,period_end desc,status);

alter table public.fixed_assets enable row level security;
alter table public.asset_depreciation_runs enable row level security;
alter table public.asset_depreciation_lines enable row level security;
create policy fixed_assets_read on public.fixed_assets for select to authenticated
  using (private.has_role(org_id,array['owner','administrator','accountant','finance_manager','approver','auditor','viewer']::public.member_role[]));
create policy asset_depreciation_runs_read on public.asset_depreciation_runs for select to authenticated
  using (private.has_role(org_id,array['owner','administrator','accountant','finance_manager','approver','auditor','viewer']::public.member_role[]));
create policy asset_depreciation_lines_read on public.asset_depreciation_lines for select to authenticated
  using (private.has_role(org_id,array['owner','administrator','accountant','finance_manager','approver','auditor','viewer']::public.member_role[]));
grant select on public.fixed_assets,public.asset_depreciation_runs,public.asset_depreciation_lines to authenticated;
revoke all on public.fixed_assets,public.asset_depreciation_runs,public.asset_depreciation_lines from anon;
revoke insert,update,delete on public.fixed_assets,public.asset_depreciation_runs,public.asset_depreciation_lines from authenticated;

create trigger audit_fixed_assets after insert or update or delete on public.fixed_assets
  for each row execute function private.audit_row();
create trigger audit_asset_depreciation_runs after insert or update or delete on public.asset_depreciation_runs
  for each row execute function private.audit_row();
create trigger audit_asset_depreciation_lines after insert or update or delete on public.asset_depreciation_lines
  for each row execute function private.audit_row();

create or replace function public.register_fixed_asset(
  p_org uuid,p_asset_code text,p_name text,p_description text,p_acquisition_date date,p_in_service_date date,
  p_cost numeric,p_residual_value numeric,p_useful_life_months integer,p_asset_account uuid,
  p_accumulated_depreciation_account uuid,p_depreciation_expense_account uuid,p_acquisition_entry uuid
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare actor uuid:=auth.uid();entry public.journal_entries%rowtype;asset_id uuid;source_debit numeric(30,4);allocated numeric(30,4);
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to register fixed assets'; end if;
  if nullif(trim(p_asset_code),'') is null or length(p_asset_code)>40 or nullif(trim(p_name),'') is null or length(p_name)>200 then raise exception 'Enter an asset code and name'; end if;
  if length(coalesce(p_description,''))>1000 then raise exception 'Asset description is too long'; end if;
  if p_acquisition_date is null or p_in_service_date is null or p_in_service_date<p_acquisition_date then raise exception 'Enter valid acquisition and in-service dates'; end if;
  if p_cost is null or p_cost<=0 or p_cost::text in ('NaN','Infinity','-Infinity') or p_cost<>round(p_cost,4) then raise exception 'Asset cost must be finite, positive, and have at most four decimal places'; end if;
  if p_residual_value is null or p_residual_value<0 or p_residual_value>p_cost or p_residual_value::text in ('NaN','Infinity','-Infinity') or p_residual_value<>round(p_residual_value,4) then raise exception 'Residual value must be between zero and cost'; end if;
  if p_useful_life_months is null or p_useful_life_months not between 1 and 1200 then raise exception 'Useful life must be between 1 and 1200 months'; end if;
  if not exists(select 1 from public.organizations o where o.id=p_org and o.accounting_method='accrual') then raise exception 'Fixed-asset depreciation requires accrual accounting'; end if;
  select * into entry from public.journal_entries where org_id=p_org and id=p_acquisition_entry for update;
  if not found or entry.status<>'posted' then raise exception 'Asset acquisition must reference a posted journal entry in this organization'; end if;
  if entry.entry_kind<>'general' then raise exception 'Asset acquisition must use a posted general journal entry'; end if;
  if entry.entry_date<>p_acquisition_date then raise exception 'Asset acquisition date must match the posted journal date'; end if;
  if not exists(select 1 from public.organizations o where o.id=p_org and o.base_currency=entry.currency and entry.exchange_rate=1) then raise exception 'Register assets only from base-currency acquisition journals until FX asset accounting is supported'; end if;
  if round((p_cost-p_residual_value)/p_useful_life_months,4)<=0 then raise exception 'Monthly straight-line depreciation is below the supported currency precision'; end if;
  if not exists(select 1 from public.accounts a where a.org_id=p_org and a.id=p_asset_account and a.type='asset' and a.is_active and a.reporting_class is null and a.normal_balance='debit') then raise exception 'Choose an active, unclassified fixed asset account'; end if;
  if not exists(select 1 from public.accounts a where a.org_id=p_org and a.id=p_accumulated_depreciation_account and a.type='asset' and a.is_active and a.reporting_class='accumulated_depreciation') then raise exception 'Choose an active contra-asset account classified as accumulated depreciation'; end if;
  if not exists(select 1 from public.accounts a where a.org_id=p_org and a.id=p_depreciation_expense_account and a.type='expense' and a.is_active and a.normal_balance='debit') then raise exception 'Choose an active depreciation expense account'; end if;
  select coalesce(sum(l.base_debit-l.base_credit),0) into source_debit from public.journal_lines l
    where l.org_id=p_org and l.entry_id=p_acquisition_entry and l.account_id=p_asset_account;
  select coalesce(sum(a.cost),0) into allocated from public.fixed_assets a where a.org_id=p_org and a.acquisition_entry_id=p_acquisition_entry and a.asset_account_id=p_asset_account;
  if p_cost+allocated>source_debit then raise exception 'Registered asset costs exceed the posted fixed-asset debit in the acquisition journal'; end if;
  insert into public.fixed_assets(org_id,asset_code,name,description,acquisition_date,in_service_date,cost,residual_value,useful_life_months,asset_account_id,
    accumulated_depreciation_account_id,depreciation_expense_account_id,acquisition_entry_id,created_by)
  values(p_org,trim(p_asset_code),trim(p_name),nullif(trim(p_description),''),p_acquisition_date,p_in_service_date,p_cost,p_residual_value,p_useful_life_months,
    p_asset_account,p_accumulated_depreciation_account,p_depreciation_expense_account,p_acquisition_entry,actor) returning id into asset_id;
  return asset_id;
end;
$$;

create or replace function public.create_fixed_asset_depreciation_draft(p_org uuid,p_period_end date)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid:=auth.uid();period_start date;period_end date;org_currency char(3);run_id uuid;journal_id uuid;lines jsonb;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to create depreciation entries'; end if;
  if p_period_end is null then raise exception 'Depreciation period end is required'; end if;
  period_start:=date_trunc('month',p_period_end)::date;
  period_end:=(date_trunc('month',p_period_end)+interval '1 month - 1 day')::date;
  if p_period_end<>period_end then raise exception 'Choose the final calendar day of the depreciation month'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_org::text||period_end::text,2));
  if not exists(select 1 from public.organizations o where o.id=p_org and o.accounting_method='accrual') then raise exception 'Fixed-asset depreciation requires accrual accounting'; end if;
  perform private.assert_open_period(p_org,period_end);
  if exists(
    select 1 from public.fixed_assets a
    cross join lateral generate_series(
      date_trunc('month',a.in_service_date)::date,
      (period_start-interval '1 month')::date,
      interval '1 month'
    ) m(month_start)
    where a.org_id=p_org and a.status='active' and a.in_service_date<=period_end
      and ((extract(year from m.month_start)-extract(year from a.in_service_date))*12+extract(month from m.month_start)-extract(month from a.in_service_date)+1)<=a.useful_life_months
      and not exists(select 1 from public.asset_depreciation_lines dl where dl.org_id=a.org_id and dl.asset_id=a.id
        and dl.period_end=(m.month_start+interval '1 month - 1 day')::date and dl.status='posted')
  ) then raise exception 'Post every earlier eligible monthly depreciation period before continuing'; end if;
  if not exists(select 1 from public.fixed_assets a where a.org_id=p_org and a.status='active' and a.in_service_date<=period_end
      and ((extract(year from period_end)-extract(year from a.in_service_date))*12+extract(month from period_end)-extract(month from a.in_service_date)+1)<=a.useful_life_months
      and not exists(select 1 from public.asset_depreciation_lines dl where dl.org_id=a.org_id and dl.asset_id=a.id and dl.period_end=period_end and dl.status<>'reversed')) then
    raise exception 'No active, not-yet-depreciated fixed assets are eligible for this month';
  end if;
  insert into public.asset_depreciation_runs(org_id,period_start,period_end,created_by)
    values(p_org,period_start,period_end,actor) returning id into run_id;
  insert into public.asset_depreciation_lines(org_id,run_id,asset_id,period_end,amount)
  select p_org,run_id,a.id,period_end,
    least(round((a.cost-a.residual_value)/a.useful_life_months,4),
      (a.cost-a.residual_value)-round((a.cost-a.residual_value)/a.useful_life_months,4)*(
        (extract(year from period_end)-extract(year from a.in_service_date))*12+extract(month from period_end)-extract(month from a.in_service_date)
      ))
  from public.fixed_assets a
  where a.org_id=p_org and a.status='active' and a.in_service_date<=period_end
    and ((extract(year from period_end)-extract(year from a.in_service_date))*12+extract(month from period_end)-extract(month from a.in_service_date)+1)<=a.useful_life_months
    and not exists(select 1 from public.asset_depreciation_lines dl where dl.org_id=a.org_id and dl.asset_id=a.id and dl.period_end=period_end and dl.status<>'reversed');
  select jsonb_agg(x.line order by x.account_id,x.side) into lines from (
    select fa.depreciation_expense_account_id account_id,1 side,jsonb_build_object('account_id',fa.depreciation_expense_account_id,'debit',dl.amount::text,'credit','0','memo','Depreciation · '||fa.asset_code) line
    from public.asset_depreciation_lines dl join public.fixed_assets fa on fa.org_id=dl.org_id and fa.id=dl.asset_id where dl.org_id=p_org and dl.run_id=run_id
    union all
    select fa.accumulated_depreciation_account_id,2,jsonb_build_object('account_id',fa.accumulated_depreciation_account_id,'debit','0','credit',dl.amount::text,'memo','Accumulated depreciation · '||fa.asset_code)
    from public.asset_depreciation_lines dl join public.fixed_assets fa on fa.org_id=dl.org_id and fa.id=dl.asset_id where dl.org_id=p_org and dl.run_id=run_id
  ) x;
  select base_currency into org_currency from public.organizations where id=p_org;
  journal_id:=public.create_journal_entry_draft(p_org,period_end,'DEP-'||to_char(period_end,'YYYY-MM'),'Monthly straight-line depreciation',org_currency,1,'depreciation',lines);
  update public.asset_depreciation_runs set journal_entry_id=journal_id where org_id=p_org and id=run_id;
  perform public.submit_journal_entry(journal_id);
  return journal_id;
end;
$$;

create or replace function private.guard_fixed_asset_entry()
returns trigger language plpgsql set search_path = ''
as $$
declare run public.asset_depreciation_runs%rowtype;
begin
  if new.status is not distinct from old.status then return new; end if;
  if new.status='reversed' and new.entry_kind<>'depreciation' and exists(
    select 1 from public.fixed_assets a where a.org_id=new.org_id and a.acquisition_entry_id=new.id
  ) then raise exception 'A fixed-asset acquisition cannot be reversed while assets are registered'; end if;
  if new.entry_kind<>'depreciation' or new.status not in ('submitted','pending_approval','approved','posted') then return new; end if;
  select * into run from public.asset_depreciation_runs where org_id=new.org_id and journal_entry_id=new.id for update;
  if not found then raise exception 'Depreciation entry must be linked to its source depreciation run'; end if;
  perform private.assert_open_period(new.org_id,new.entry_date);
  if new.entry_date<>run.period_end or run.status not in ('draft','submitted') then raise exception 'Depreciation journal does not match an open source run'; end if;
  if exists(
    (select l.account_id,l.debit,l.credit from public.journal_lines l where l.org_id=new.org_id and l.entry_id=new.id
      except all
     select x.account_id,x.debit,x.credit from (
       select a.depreciation_expense_account_id account_id,dl.amount debit,0::numeric credit from public.asset_depreciation_lines dl join public.fixed_assets a on a.org_id=dl.org_id and a.id=dl.asset_id where dl.org_id=new.org_id and dl.run_id=run.id
       union all
       select a.accumulated_depreciation_account_id,0::numeric,dl.amount from public.asset_depreciation_lines dl join public.fixed_assets a on a.org_id=dl.org_id and a.id=dl.asset_id where dl.org_id=new.org_id and dl.run_id=run.id
     ) x)
    union all
    (select x.account_id,x.debit,x.credit from (
       select a.depreciation_expense_account_id account_id,dl.amount debit,0::numeric credit from public.asset_depreciation_lines dl join public.fixed_assets a on a.org_id=dl.org_id and a.id=dl.asset_id where dl.org_id=new.org_id and dl.run_id=run.id
       union all
       select a.accumulated_depreciation_account_id,0::numeric,dl.amount from public.asset_depreciation_lines dl join public.fixed_assets a on a.org_id=dl.org_id and a.id=dl.asset_id where dl.org_id=new.org_id and dl.run_id=run.id
     ) x
      except all
     select l.account_id,l.debit,l.credit from public.journal_lines l where l.org_id=new.org_id and l.entry_id=new.id)
  ) then raise exception 'Depreciation journal lines differ from the calculated asset schedule'; end if;
  return new;
end;
$$;
revoke all on function private.guard_fixed_asset_entry() from public,anon,authenticated;
drop trigger if exists guard_fixed_asset_entry on public.journal_entries;
create trigger guard_fixed_asset_entry before update of status on public.journal_entries
  for each row execute function private.guard_fixed_asset_entry();

create or replace function private.sync_fixed_asset_run_status()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare next_status text;
begin
  if old.status is not distinct from new.status then return new; end if;
  if new.entry_kind<>'depreciation' then return new; end if;
  next_status:=case when new.status='posted' then 'posted' when new.status='reversed' then 'reversed'
    when new.status in ('submitted','pending_approval','approved') then 'submitted'
    when new.status='draft' and new.rejection_reason is not null then 'draft' else null end;
  if next_status is not null then
    update public.asset_depreciation_runs set status=next_status where org_id=new.org_id and journal_entry_id=new.id;
    update public.asset_depreciation_lines set status=next_status where org_id=new.org_id and run_id=(select r.id from public.asset_depreciation_runs r where r.org_id=new.org_id and r.journal_entry_id=new.id);
  end if;
  return new;
end;
$$;
revoke all on function private.sync_fixed_asset_run_status() from public,anon,authenticated;
drop trigger if exists sync_fixed_asset_run_status on public.journal_entries;
create trigger sync_fixed_asset_run_status after update of status on public.journal_entries
  for each row execute function private.sync_fixed_asset_run_status();

create or replace view public.fixed_assets_exact with (security_invoker=true) as
select a.id,a.org_id,a.asset_code,a.name,a.description,a.acquisition_date,a.in_service_date,a.cost::text cost,a.residual_value::text residual_value,
  a.useful_life_months,a.asset_account_id,asset_account.code asset_account_code,asset_account.name asset_account_name,
  a.accumulated_depreciation_account_id,accum_account.code accumulated_depreciation_account_code,
  a.depreciation_expense_account_id,expense_account.code depreciation_expense_account_code,a.acquisition_entry_id,a.status,a.created_by,a.created_at,
  coalesce(sum(dl.amount) filter(where dl.status='posted'),0)::text accumulated_depreciation,
  (a.cost-coalesce(sum(dl.amount) filter(where dl.status='posted'),0))::text net_book_value
from public.fixed_assets a
join public.accounts asset_account on asset_account.org_id=a.org_id and asset_account.id=a.asset_account_id
join public.accounts accum_account on accum_account.org_id=a.org_id and accum_account.id=a.accumulated_depreciation_account_id
join public.accounts expense_account on expense_account.org_id=a.org_id and expense_account.id=a.depreciation_expense_account_id
left join public.asset_depreciation_lines dl on dl.org_id=a.org_id and dl.asset_id=a.id
group by a.id,asset_account.code,asset_account.name,accum_account.code,expense_account.code;
revoke all on public.fixed_assets_exact from public,anon,authenticated;
grant select on public.fixed_assets_exact to authenticated;

revoke all on function public.register_fixed_asset(uuid,text,text,text,date,date,numeric,numeric,integer,uuid,uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.create_fixed_asset_depreciation_draft(uuid,date) from public,anon,authenticated;
grant execute on function public.register_fixed_asset(uuid,text,text,text,date,date,numeric,numeric,integer,uuid,uuid,uuid,uuid) to authenticated;
grant execute on function public.create_fixed_asset_depreciation_draft(uuid,date) to authenticated;
