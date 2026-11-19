-- Fixed-asset disposals are traceable journals and remain subject to the
-- standard maker-checker approval and posting workflow.
alter table public.journal_entries drop constraint if exists journal_entries_entry_kind_check;
alter table public.journal_entries add constraint journal_entries_entry_kind_check check (entry_kind in (
  'general','opening_balance','income','expense','payment','bank_transfer','bank_deposit','bank_withdrawal',
  'reversal','closing','sales_invoice','purchase_bill','customer_payment','supplier_payment','depreciation','payroll','asset_disposal'
));

create table public.fixed_asset_disposals (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  asset_id uuid not null,
  journal_entry_id uuid not null,
  disposal_date date not null,
  proceeds numeric(20,4) not null check (proceeds>=0 and proceeds::text not in ('NaN','Infinity','-Infinity')),
  proceeds_account_id uuid,
  gain_account_id uuid,
  loss_account_id uuid,
  status text not null default 'submitted' check (status in ('submitted','posted','reversed')),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique(org_id,id),
  foreign key(org_id,asset_id) references public.fixed_assets(org_id,id) on delete restrict,
  foreign key(org_id,journal_entry_id) references public.journal_entries(org_id,id) on delete restrict,
  foreign key(org_id,proceeds_account_id) references public.accounts(org_id,id) on delete restrict,
  foreign key(org_id,gain_account_id) references public.accounts(org_id,id) on delete restrict,
  foreign key(org_id,loss_account_id) references public.accounts(org_id,id) on delete restrict,
  check ((proceeds=0 and proceeds_account_id is null) or (proceeds>0 and proceeds_account_id is not null)),
  check (gain_account_id is null or loss_account_id is null)
);
create unique index fixed_asset_disposals_one_active_idx on public.fixed_asset_disposals(org_id,asset_id) where status<>'reversed';
create index fixed_asset_disposals_journal_idx on public.fixed_asset_disposals(org_id,journal_entry_id);
alter table public.fixed_asset_disposals enable row level security;
create policy fixed_asset_disposals_read on public.fixed_asset_disposals for select to authenticated
  using(private.has_role(org_id,array['owner','administrator','accountant','finance_manager','approver','auditor','viewer']::public.member_role[]));
grant select on public.fixed_asset_disposals to authenticated;
revoke all on public.fixed_asset_disposals from anon;
revoke insert,update,delete on public.fixed_asset_disposals from authenticated;
create trigger audit_fixed_asset_disposals after insert or update or delete on public.fixed_asset_disposals
  for each row execute function private.audit_row();

create or replace function public.create_fixed_asset_disposal_draft(
  p_org uuid,p_asset uuid,p_disposal_date date,p_proceeds numeric,p_proceeds_account uuid,p_gain_account uuid,p_loss_account uuid
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid:=auth.uid(); a public.fixed_assets%rowtype; dep numeric(30,4); carrying numeric(30,4); gain numeric(30,4); loss numeric(30,4);
  journal_id uuid; disposal_id uuid; org_currency char(3); lines jsonb; month_end date;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to dispose fixed assets'; end if;
  if p_disposal_date is null or p_proceeds is null or p_proceeds<0 or p_proceeds::text in ('NaN','Infinity','-Infinity') or p_proceeds<>round(p_proceeds,4) then raise exception 'Enter a valid disposal date and non-negative proceeds'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_org::text||p_asset::text,3));
  select * into a from public.fixed_assets where org_id=p_org and id=p_asset for update;
  if not found or a.status<>'active' then raise exception 'Active fixed asset not found'; end if;
  if p_disposal_date<a.in_service_date then raise exception 'Disposal date cannot precede the in-service date'; end if;
  if p_disposal_date<>(date_trunc('month',p_disposal_date)+interval '1 month - 1 day')::date then raise exception 'Choose the final calendar day of the disposal month'; end if;
  perform private.assert_open_period(p_org,p_disposal_date);
  if exists(select 1 from public.asset_depreciation_lines dl where dl.org_id=p_org and dl.asset_id=p_asset and dl.period_end<=p_disposal_date and dl.status not in ('posted','reversed')) then
    raise exception 'Resolve pending depreciation journals through the disposal date first';
  end if;
  if exists(select 1 from public.asset_depreciation_lines dl where dl.org_id=p_org and dl.asset_id=p_asset and dl.period_end<=p_disposal_date and dl.status='reversed') then
    raise exception 'Reversed depreciation through the disposal date must be corrected before disposal';
  end if;
  if exists(select 1 from public.asset_depreciation_lines dl where dl.org_id=p_org and dl.asset_id=p_asset and dl.period_end>p_disposal_date and dl.status<>'reversed') then
    raise exception 'Resolve depreciation after the proposed disposal month before disposal';
  end if;
  if exists(
    select 1 from generate_series(date_trunc('month',a.in_service_date)::date,date_trunc('month',p_disposal_date)::date,interval '1 month') m(month_start)
    where ((extract(year from m.month_start)-extract(year from a.in_service_date))*12+extract(month from m.month_start)-extract(month from a.in_service_date)+1)<=a.useful_life_months
      and not exists(select 1 from public.asset_depreciation_lines dl where dl.org_id=p_org and dl.asset_id=p_asset
        and dl.period_end=(m.month_start+interval '1 month - 1 day')::date and dl.status='posted')
  ) then raise exception 'Post every eligible monthly depreciation period through disposal before continuing'; end if;
  select coalesce(sum(dl.amount),0)::numeric(30,4) into dep from public.asset_depreciation_lines dl
    where dl.org_id=p_org and dl.asset_id=p_asset and dl.status='posted' and dl.period_end<=p_disposal_date;
  if dep>a.cost-a.residual_value then raise exception 'Posted depreciation exceeds the depreciable asset cost'; end if;
  carrying:=a.cost-dep;
  if p_proceeds>0 then
    if not exists(select 1 from public.accounts x where x.org_id=p_org and x.id=p_proceeds_account and x.is_active and x.type='asset' and x.reporting_class in ('cash','bank')) then
      raise exception 'Proceeds account must be an active cash or bank account';
    end if;
  elsif p_proceeds_account is not null then raise exception 'A proceeds account is not allowed when proceeds are zero'; end if;
  gain:=greatest(p_proceeds-carrying,0); loss:=greatest(carrying-p_proceeds,0);
  if gain>0 then
    if not exists(select 1 from public.accounts x where x.org_id=p_org and x.id=p_gain_account and x.is_active and x.type='revenue') then raise exception 'Select an active gain account'; end if;
  elsif p_gain_account is not null then raise exception 'Gain account is only used when proceeds exceed carrying value'; end if;
  if loss>0 then
    if not exists(select 1 from public.accounts x where x.org_id=p_org and x.id=p_loss_account and x.is_active and x.type='expense') then raise exception 'Select an active loss account'; end if;
  elsif p_loss_account is not null then raise exception 'Loss account is only used when carrying value exceeds proceeds'; end if;
  select base_currency into org_currency from public.organizations where id=p_org;
  select jsonb_agg(q.line order by q.seq) into lines from (
    select 1 seq,jsonb_build_object('account_id',p_proceeds_account,'debit',p_proceeds::text,'credit','0','memo','Disposal proceeds · '||a.asset_code) line where p_proceeds>0
    union all select 2,jsonb_build_object('account_id',a.accumulated_depreciation_account_id,'debit',dep::text,'credit','0','memo','Remove accumulated depreciation · '||a.asset_code) where dep>0
    union all select 3,jsonb_build_object('account_id',p_loss_account,'debit',loss::text,'credit','0','memo','Loss on disposal · '||a.asset_code) where loss>0
    union all select 4,jsonb_build_object('account_id',a.asset_account_id,'debit','0','credit',a.cost::text,'memo','Remove asset cost · '||a.asset_code)
    union all select 5,jsonb_build_object('account_id',p_gain_account,'debit','0','credit',gain::text,'memo','Gain on disposal · '||a.asset_code) where gain>0
  ) q;
  journal_id:=public.create_journal_entry_draft(p_org,p_disposal_date,'DISP-'||a.asset_code,'Disposal of '||a.name,org_currency,1,'asset_disposal',lines);
  insert into public.fixed_asset_disposals(org_id,asset_id,journal_entry_id,disposal_date,proceeds,proceeds_account_id,gain_account_id,loss_account_id,created_by)
    values(p_org,p_asset,journal_id,p_disposal_date,p_proceeds,p_proceeds_account,case when gain>0 then p_gain_account end,case when loss>0 then p_loss_account end,actor)
    returning id into disposal_id;
  perform public.submit_journal_entry(journal_id);
  return journal_id;
end;
$$;

create or replace function private.guard_fixed_asset_disposal_entry()
returns trigger language plpgsql set search_path = ''
as $$
declare d public.fixed_asset_disposals%rowtype; a public.fixed_assets%rowtype; dep numeric(30,4); gain numeric(30,4); loss numeric(30,4);
begin
  if new.entry_kind<>'asset_disposal' or new.status not in ('submitted','pending_approval','approved','posted') then return new; end if;
  select * into d from public.fixed_asset_disposals where org_id=new.org_id and journal_entry_id=new.id for update;
  if not found then raise exception 'Disposal journal must be linked to its source asset record'; end if;
  select * into a from public.fixed_assets where org_id=d.org_id and id=d.asset_id for update;
  if not found or (a.status<>'active' and new.status<>'posted') then raise exception 'Asset is no longer available for disposal'; end if;
  if not exists(select 1 from public.accounts x where x.org_id=a.org_id and x.id=a.asset_account_id and x.is_active and x.type='asset')
    or not exists(select 1 from public.accounts x where x.org_id=a.org_id and x.id=a.accumulated_depreciation_account_id and x.is_active and x.type='asset' and x.reporting_class='accumulated_depreciation') then
    raise exception 'Fixed-asset and accumulated-depreciation accounts must remain active and correctly classified';
  end if;
  if d.proceeds>0 and not exists(select 1 from public.accounts x where x.org_id=d.org_id and x.id=d.proceeds_account_id and x.is_active and x.type='asset' and x.reporting_class in ('cash','bank')) then raise exception 'Disposal proceeds account must remain active and classified'; end if;
  if d.gain_account_id is not null and not exists(select 1 from public.accounts x where x.org_id=d.org_id and x.id=d.gain_account_id and x.is_active and x.type='revenue') then raise exception 'Disposal gain account must remain active'; end if;
  if d.loss_account_id is not null and not exists(select 1 from public.accounts x where x.org_id=d.org_id and x.id=d.loss_account_id and x.is_active and x.type='expense') then raise exception 'Disposal loss account must remain active'; end if;
  if new.entry_date<>d.disposal_date then raise exception 'Disposal journal date cannot be changed'; end if;
  if d.disposal_date<>(date_trunc('month',d.disposal_date)+interval '1 month - 1 day')::date then raise exception 'Disposal date must be the final day of its month'; end if;
  perform private.assert_open_period(new.org_id,new.entry_date);
  if exists(select 1 from public.asset_depreciation_lines dl where dl.org_id=d.org_id and dl.asset_id=d.asset_id and dl.period_end<=d.disposal_date and dl.status not in ('posted','reversed')) then raise exception 'Resolve depreciation through disposal date first'; end if;
  if exists(select 1 from public.asset_depreciation_lines dl where dl.org_id=d.org_id and dl.asset_id=d.asset_id and dl.period_end<=d.disposal_date and dl.status='reversed') then raise exception 'Correct reversed depreciation through disposal date first'; end if;
  if exists(select 1 from public.asset_depreciation_lines dl where dl.org_id=d.org_id and dl.asset_id=d.asset_id and dl.period_end>d.disposal_date and dl.status<>'reversed') then raise exception 'Resolve depreciation after disposal month first'; end if;
  if exists(
    select 1 from generate_series(date_trunc('month',a.in_service_date)::date,date_trunc('month',d.disposal_date)::date,interval '1 month') m(month_start)
    where ((extract(year from m.month_start)-extract(year from a.in_service_date))*12+extract(month from m.month_start)-extract(month from a.in_service_date)+1)<=a.useful_life_months
      and not exists(select 1 from public.asset_depreciation_lines dl where dl.org_id=d.org_id and dl.asset_id=d.asset_id
        and dl.period_end=(m.month_start+interval '1 month - 1 day')::date and dl.status='posted')
  ) then raise exception 'Post every eligible depreciation period through disposal first'; end if;
  select coalesce(sum(dl.amount),0)::numeric(30,4) into dep from public.asset_depreciation_lines dl where dl.org_id=d.org_id and dl.asset_id=d.asset_id and dl.status='posted' and dl.period_end<=d.disposal_date;
  if dep>a.cost-a.residual_value then raise exception 'Posted depreciation exceeds the depreciable asset cost'; end if;
  gain:=greatest(d.proceeds-(a.cost-dep),0); loss:=greatest((a.cost-dep)-d.proceeds,0);
  if exists(
    (select l.account_id,l.debit,l.credit from public.journal_lines l where l.org_id=new.org_id and l.entry_id=new.id
      except all
     select x.account_id,x.debit,x.credit from (
       select d.proceeds_account_id account_id,d.proceeds debit,0::numeric credit where d.proceeds>0
       union all select a.accumulated_depreciation_account_id,dep,0::numeric where dep>0
       union all select d.loss_account_id,loss,0::numeric where loss>0
       union all select a.asset_account_id,0::numeric,a.cost
       union all select d.gain_account_id,0::numeric,gain where gain>0
     ) x)
    union all
    (select x.account_id,x.debit,x.credit from (
       select d.proceeds_account_id account_id,d.proceeds debit,0::numeric credit where d.proceeds>0
       union all select a.accumulated_depreciation_account_id,dep,0::numeric where dep>0
       union all select d.loss_account_id,loss,0::numeric where loss>0
       union all select a.asset_account_id,0::numeric,a.cost
       union all select d.gain_account_id,0::numeric,gain where gain>0
     ) x except all select l.account_id,l.debit,l.credit from public.journal_lines l where l.org_id=new.org_id and l.entry_id=new.id)
  ) then raise exception 'Disposal journal lines differ from the calculated asset disposal'; end if;
  return new;
end;
$$;
revoke all on function private.guard_fixed_asset_disposal_entry() from public,anon,authenticated;
create trigger guard_fixed_asset_disposal_entry before update of status on public.journal_entries
  for each row execute function private.guard_fixed_asset_disposal_entry();

create or replace function private.guard_depreciation_after_disposal()
returns trigger language plpgsql set search_path = ''
as $$
declare run_id uuid; period_end date;
begin
  if new.entry_kind<>'depreciation' or new.status not in ('submitted','pending_approval','approved','posted') then return new; end if;
  select r.id,r.period_end into run_id,period_end from public.asset_depreciation_runs r
    where r.org_id=new.org_id and r.journal_entry_id=new.id for update;
  if run_id is null then return new; end if;
  if exists(select 1 from public.asset_depreciation_lines dl join public.fixed_asset_disposals d on d.org_id=dl.org_id and d.asset_id=dl.asset_id
    where dl.org_id=new.org_id and dl.run_id=run_id and d.status<>'reversed' and d.disposal_date<period_end) then
    raise exception 'Depreciation cannot be submitted after an asset disposal has been initiated';
  end if;
  return new;
end;
$$;
revoke all on function private.guard_depreciation_after_disposal() from public,anon,authenticated;
create trigger guard_depreciation_after_disposal before update of status on public.journal_entries
  for each row execute function private.guard_depreciation_after_disposal();

create or replace function private.sync_fixed_asset_disposal_status()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare d public.fixed_asset_disposals%rowtype;
begin
  if old.status is not distinct from new.status then return new; end if;
  if new.entry_kind='asset_disposal' and new.status<>'reversed' then
    update public.fixed_asset_disposals set status=case when new.status='posted' then 'posted' else 'submitted' end
      where org_id=new.org_id and journal_entry_id=new.id returning * into d;
    if found and new.status='posted' then update public.fixed_assets set status='disposed' where org_id=d.org_id and id=d.asset_id; end if;
  elsif new.entry_kind='reversal' and new.reverses_id is not null and new.status='posted' then
    select * into d from public.fixed_asset_disposals where org_id=new.org_id and journal_entry_id=new.reverses_id for update;
    if found then
      update public.fixed_asset_disposals set status='reversed' where id=d.id;
      update public.fixed_assets set status='active' where org_id=d.org_id and id=d.asset_id;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.sync_fixed_asset_disposal_status() from public,anon,authenticated;
create trigger sync_fixed_asset_disposal_status after update of status on public.journal_entries
  for each row execute function private.sync_fixed_asset_disposal_status();

revoke all on function public.create_fixed_asset_disposal_draft(uuid,uuid,date,numeric,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.create_fixed_asset_disposal_draft(uuid,uuid,date,numeric,uuid,uuid,uuid) to authenticated;
