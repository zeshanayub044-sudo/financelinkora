-- Approved fiscal-year closes clear temporary accounts and transfer net
-- earnings to equity. Posted ledger entries remain immutable.
alter table public.accounting_periods add constraint accounting_periods_org_id_id_key unique(org_id,id);
create table public.fiscal_year_closings (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  period_id uuid not null references public.accounting_periods(id) on delete restrict,
  fiscal_year_start date not null,
  fiscal_year_end date not null,
  retained_earnings_account_id uuid not null,
  journal_entry_id uuid not null unique references public.journal_entries(id) on delete restrict,
  reversal_entry_id uuid references public.journal_entries(id) on delete restrict,
  reversal_date date,
  status text not null default 'submitted' check(status in ('submitted','posted','reversed','voided')),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  check(fiscal_year_end>=fiscal_year_start),
  check((status='reversed' and reversal_entry_id is not null and reversal_date is not null)
    or (status<>'reversed' and reversal_entry_id is null and reversal_date is null)),
  unique(org_id,id),
  foreign key(org_id,retained_earnings_account_id) references public.accounts(org_id,id) on delete restrict,
  foreign key(org_id,period_id) references public.accounting_periods(org_id,id) on delete restrict
);
create unique index fiscal_year_closings_one_active_idx on public.fiscal_year_closings(org_id,fiscal_year_start)
  where status not in ('reversed','voided');
create index fiscal_year_closings_end_idx on public.fiscal_year_closings(org_id,fiscal_year_end desc,status);
alter table public.fiscal_year_closings enable row level security;
create policy fiscal_year_closings_read on public.fiscal_year_closings for select to authenticated
  using(private.has_role(org_id,array['owner','administrator','finance_manager','accountant','approver','auditor','viewer']::public.member_role[]));
grant select on public.fiscal_year_closings to authenticated;
revoke all on public.fiscal_year_closings from anon;
revoke insert,update,delete on public.fiscal_year_closings from authenticated;
create trigger audit_fiscal_year_closings after insert or update or delete on public.fiscal_year_closings
  for each row execute function private.audit_row();

create or replace function private.is_fiscal_year_end_period(p_org uuid,p_start date,p_end date)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists(
    select 1 from public.organizations o
    cross join lateral(select extract(year from p_end)::integer - case when o.fy_start_month=1 then 0 else 1 end start_year) y
    where o.id=p_org and p_start=date_trunc('month',p_end)::date
      and p_end=(make_date(y.start_year+1,o.fy_start_month,1)-1)
  );
$$;

create or replace function private.guard_fiscal_year_close()
returns trigger language plpgsql set search_path = ''
as $$
declare c public.fiscal_year_closings%rowtype;p public.accounting_periods%rowtype;expected_count integer;actual_count integer;
begin
  if new.entry_kind='closing' and new.status in ('submitted','pending_approval','approved','posted') then
    select * into c from public.fiscal_year_closings where org_id=new.org_id and journal_entry_id=new.id for update;
    if not found or c.status<>'submitted' then raise exception 'Closing journal must be linked to an active fiscal-year close'; end if;
    if new.status<>'posted' then return new; end if;
    select * into p from public.accounting_periods where org_id=c.org_id and id=c.period_id for update;
    if not found or p.is_closed or p.end_date<>c.fiscal_year_end or not private.is_fiscal_year_end_period(c.org_id,p.start_date,p.end_date) then
      raise exception 'Fiscal-year closing period is no longer valid or open';
    end if;
    if new.entry_date<>c.fiscal_year_end then raise exception 'Fiscal-year closing date cannot be changed'; end if;
    if exists(select 1 from public.journal_entries e where e.org_id=c.org_id and e.id<>new.id and e.entry_date between c.fiscal_year_start and c.fiscal_year_end
      and e.status in ('submitted','pending_approval','approved')) then raise exception 'Resolve pending journal entries for the financial year before posting the close'; end if;
    if not exists(select 1 from public.accounts a where a.org_id=c.org_id and a.id=c.retained_earnings_account_id and a.is_active and a.type='equity') then
      raise exception 'Retained earnings account must remain active and classified as equity';
    end if;
    perform private.assert_open_period(c.org_id,new.entry_date);
    select count(*) into expected_count from private.fiscal_year_close_lines(c.org_id,c.fiscal_year_start,c.fiscal_year_end,c.retained_earnings_account_id);
    select count(*) into actual_count from public.journal_lines l where l.org_id=new.org_id and l.entry_id=new.id;
    if expected_count<>actual_count or exists(
      (select l.account_id,l.debit,l.credit from public.journal_lines l where l.org_id=new.org_id and l.entry_id=new.id
        except all select x.account_id,x.debit,x.credit from private.fiscal_year_close_lines(c.org_id,c.fiscal_year_start,c.fiscal_year_end,c.retained_earnings_account_id) x)
      union all
      (select x.account_id,x.debit,x.credit from private.fiscal_year_close_lines(c.org_id,c.fiscal_year_start,c.fiscal_year_end,c.retained_earnings_account_id) x
        except all select l.account_id,l.debit,l.credit from public.journal_lines l where l.org_id=new.org_id and l.entry_id=new.id)
    ) then raise exception 'Closing journal no longer matches posted fiscal-year balances; reject and prepare a fresh closing journal'; end if;
  elsif new.status='posted' and new.entry_kind='reversal' and exists(select 1 from public.fiscal_year_closings source
    join public.fiscal_year_closings later on later.org_id=source.org_id and later.status='posted' and later.fiscal_year_end>source.fiscal_year_end
    where source.org_id=new.org_id and source.journal_entry_id=new.reverses_id and source.status='posted') then
    raise exception 'Reverse later fiscal-year closes first';
  elsif new.status='posted' and exists(select 1 from public.fiscal_year_closings c where c.org_id=new.org_id and c.status='submitted'
    and new.entry_date between c.fiscal_year_start and c.fiscal_year_end) then
    raise exception 'A fiscal-year close is awaiting posting; complete or reject it before posting other entries in that year';
  end if;
  return new;
end;
$$;
revoke all on function private.guard_fiscal_year_close() from public,anon,authenticated;
create trigger guard_fiscal_year_close before update of status on public.journal_entries
  for each row execute function private.guard_fiscal_year_close();

create or replace function private.guard_fiscal_year_period_lock()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.is_closed and not old.is_closed and private.is_fiscal_year_end_period(new.org_id,new.start_date,new.end_date)
    and not exists(select 1 from public.fiscal_year_closings c where c.org_id=new.org_id and c.period_id=new.id and c.status='posted') then
    raise exception 'Post the approved fiscal-year closing journal before locking the year-end period';
  end if;
  if old.is_closed and not new.is_closed and exists(select 1 from public.fiscal_year_closings c where c.org_id=new.org_id and c.period_id=new.id and c.status='posted') then
    raise exception 'Reverse the posted fiscal-year closing journal before reopening this period';
  end if;
  return new;
end;
$$;
revoke all on function private.guard_fiscal_year_period_lock() from public,anon,authenticated;
create trigger guard_fiscal_year_period_lock before update of is_closed on public.accounting_periods
  for each row execute function private.guard_fiscal_year_period_lock();

create or replace function private.sync_fiscal_year_close()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare c public.fiscal_year_closings%rowtype;
begin
  if old.status is not distinct from new.status then return new; end if;
  if new.entry_kind='closing' then
    if new.status='posted' then
      update public.fiscal_year_closings set status='posted' where org_id=new.org_id and journal_entry_id=new.id returning * into c;
      update public.accounting_periods set is_closed=true where org_id=c.org_id and start_date>=c.fiscal_year_start and end_date<=c.fiscal_year_end and not is_closed;
    elsif new.status='draft' and new.rejection_reason is not null then
      update public.fiscal_year_closings set status='voided' where org_id=new.org_id and journal_entry_id=new.id;
    end if;
  elsif new.entry_kind='reversal' and new.status='posted' and new.reverses_id is not null then
    update public.fiscal_year_closings set status='reversed',reversal_entry_id=new.id,reversal_date=new.entry_date
      where org_id=new.org_id and journal_entry_id=new.reverses_id;
  end if;
  return new;
end;
$$;
revoke all on function private.sync_fiscal_year_close() from public,anon,authenticated;
create trigger sync_fiscal_year_close after update of status on public.journal_entries
  for each row execute function private.sync_fiscal_year_close();

create or replace function private.last_closed_fiscal_year_end(p_org uuid,p_as_of date)
returns date language sql stable security definer set search_path = ''
as $$
  select max(c.fiscal_year_end) from public.fiscal_year_closings c
  where c.org_id=p_org and c.fiscal_year_end<=p_as_of
    and (c.status='posted' or (c.status='reversed' and c.reversal_date>p_as_of));
$$;
revoke all on function private.last_closed_fiscal_year_end(uuid,date) from public,anon,authenticated;

create or replace function private.assert_open_period(p_org uuid,p_date date)
returns void language plpgsql security definer set search_path = ''
as $$
declare is_closed boolean;
begin
  if exists(select 1 from public.fiscal_year_closings c where c.org_id=p_org and c.status='posted' and p_date between c.fiscal_year_start and c.fiscal_year_end) then
    raise exception 'Fiscal year is closed';
  end if;
  select p.is_closed into is_closed from public.accounting_periods p where p.org_id=p_org and p_date between p.start_date and p.end_date for update;
  if not found then raise exception 'No accounting period covers %',p_date; end if;
  if is_closed then raise exception 'Accounting period is closed'; end if;
end;
$$;
revoke all on function private.assert_open_period(uuid,date) from public,anon,authenticated;

create or replace function public.profit_and_loss(p_org uuid,p_from date,p_to date)
returns table(code text,name text,type public.account_type,amount numeric)
language sql stable security invoker set search_path = ''
as $$
  select a.code,a.name,a.type,
    case when a.type='revenue' then coalesce(sum(l.base_credit-l.base_debit),0)
         else coalesce(sum(l.base_debit-l.base_credit),0) end
  from public.accounts a
  left join public.journal_entries e on e.org_id=a.org_id and e.status in ('posted','reversed')
    and e.entry_date between p_from and p_to and e.entry_kind<>'closing'
    and not(e.entry_kind='reversal' and exists(select 1 from public.journal_entries source
      where source.org_id=e.org_id and source.id=e.reverses_id and source.entry_kind='closing'))
  left join public.journal_lines l on l.account_id=a.id and l.org_id=a.org_id and l.entry_id=e.id
  where a.org_id=p_org and a.type in ('revenue','expense')
  group by a.id,a.code,a.name,a.type order by a.code;
$$;
revoke all on function public.profit_and_loss(uuid,date,date) from public,anon,authenticated;
grant execute on function public.profit_and_loss(uuid,date,date) to authenticated;

create or replace function public.balance_sheet(p_org uuid,p_as_of date)
returns table(section text,code text,name text,balance numeric)
language sql stable security invoker set search_path = ''
as $$
  with last_close as (
    select private.last_closed_fiscal_year_end(p_org,p_as_of) fiscal_year_end
  ), account_balances as (
    select a.id,a.code,a.name,a.type,
      case when a.type='asset' then coalesce(sum(l.base_debit-l.base_credit),0)
           else coalesce(sum(l.base_credit-l.base_debit),0) end balance
    from public.accounts a
    left join public.journal_entries e on e.org_id=a.org_id and e.status in ('posted','reversed') and e.entry_date<=p_as_of
    left join public.journal_lines l on l.account_id=a.id and l.org_id=a.org_id and l.entry_id=e.id
    where a.org_id=p_org and a.type in ('asset','liability','equity') group by a.id,a.code,a.name,a.type
  ), current_earnings as (
    select coalesce(sum(l.base_credit-l.base_debit),0) amount
    from public.accounts a join public.journal_lines l on l.account_id=a.id and l.org_id=a.org_id
    join public.journal_entries e on e.id=l.entry_id and e.org_id=l.org_id cross join last_close lc
    where a.org_id=p_org and a.type in ('revenue','expense') and e.status in ('posted','reversed') and e.entry_date<=p_as_of
      and e.entry_date>coalesce(lc.fiscal_year_end,date '-infinity') and e.entry_kind<>'closing'
      and not(e.entry_kind='reversal' and exists(select 1 from public.journal_entries source
        where source.org_id=e.org_id and source.id=e.reverses_id and source.entry_kind='closing'))
  )
  select case b.type when 'asset' then 'assets' when 'liability' then 'liabilities' else 'equity' end,b.code,b.name,b.balance
    from account_balances b
  union all select 'equity','3999','Current earnings',amount from current_earnings where amount<>0
  order by 1,2;
$$;
revoke all on function public.balance_sheet(uuid,date) from public,anon,authenticated;
grant execute on function public.balance_sheet(uuid,date) to authenticated;

create or replace function public.financial_summary(p_org uuid,p_from date,p_to date,p_as_of date)
returns table(income numeric,expenses numeric,profit numeric,assets numeric,liabilities numeric,equity numeric,
  cash_balance numeric,bank_balance numeric,accounts_receivable numeric,accounts_payable numeric)
language sql stable security invoker set search_path = ''
as $$
  with period_pl as (
    select coalesce(sum(amount) filter(where type='revenue'),0) income,coalesce(sum(amount) filter(where type='expense'),0) expenses
    from public.profit_and_loss(p_org,p_from,p_to)
  ), balances as (
    select t.code,t.name,t.type,a.reporting_class,
      case when t.type in ('asset','expense') then t.debit-t.credit else t.credit-t.debit end value
    from public.trial_balance_as_of(p_org,p_as_of) t join public.accounts a on a.org_id=p_org and a.code=t.code
  ), sums as (
    select coalesce(sum(value) filter(where type='asset'),0) assets,
      coalesce(sum(value) filter(where type='liability'),0) liabilities,
      coalesce(sum(value) filter(where reporting_class='cash'),0) cash_balance,
      coalesce(sum(value) filter(where reporting_class='bank'),0) bank_balance,
      coalesce(sum(value) filter(where reporting_class='receivable'),0) accounts_receivable,
      coalesce(sum(value) filter(where reporting_class='payable'),0) accounts_payable from balances
  ), equity_total as (
    select coalesce(sum(balance),0) equity from public.balance_sheet(p_org,p_as_of) where section='equity'
  )
  select p.income,p.expenses,p.income-p.expenses,s.assets,s.liabilities,e.equity,s.cash_balance,s.bank_balance,s.accounts_receivable,s.accounts_payable
  from period_pl p cross join sums s cross join equity_total e;
$$;
revoke all on function public.financial_summary(uuid,date,date,date) from public,anon,authenticated;
grant execute on function public.financial_summary(uuid,date,date,date) to authenticated;

create or replace function public.monthly_financial_activity(p_org uuid,p_from date)
returns table(month_start date,revenue numeric,expenses numeric)
language sql stable security invoker set search_path = ''
as $$
  with months as (
    select generate_series(date_trunc('month',p_from)::date,date_trunc('month',current_date)::date,interval '1 month')::date month_start
  ), activity as (
    select date_trunc('month',e.entry_date)::date month_start,
      coalesce(sum(l.base_credit-l.base_debit) filter(where a.type='revenue'),0) revenue,
      coalesce(sum(l.base_debit-l.base_credit) filter(where a.type='expense'),0) expenses
    from public.journal_entries e join public.journal_lines l on l.entry_id=e.id and l.org_id=e.org_id
    join public.accounts a on a.id=l.account_id and a.org_id=l.org_id
    where e.org_id=p_org and e.status in ('posted','reversed') and e.entry_date>=date_trunc('month',p_from)::date
      and a.type in ('revenue','expense') and e.entry_kind<>'closing'
      and not(e.entry_kind='reversal' and exists(select 1 from public.journal_entries source where source.org_id=e.org_id and source.id=e.reverses_id and source.entry_kind='closing'))
    group by 1
  )
  select m.month_start,coalesce(a.revenue,0),coalesce(a.expenses,0) from months m left join activity a using(month_start) order by m.month_start;
$$;
revoke all on function public.monthly_financial_activity(uuid,date) from public,anon,authenticated;
grant execute on function public.monthly_financial_activity(uuid,date) to authenticated;

create or replace function public.statement_of_changes_in_equity_exact(p_org uuid,p_from date,p_to date)
returns table(line_type text,account_id uuid,code text,name text,opening_balance text,period_movement text,closing_balance text)
language plpgsql stable security invoker set search_path = ''
as $$
declare opening_earnings numeric;closing_earnings numeric;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_from is null or p_to is null or p_from>p_to then raise exception 'Choose a valid equity reporting date range'; end if;
  if not private.has_role(p_org,array['owner','administrator','finance_manager','accountant','approver','auditor','viewer']::public.member_role[]) then raise exception 'Not authorized to view this organization'; end if;
  select coalesce(sum(l.base_credit-l.base_debit),0) into opening_earnings
  from public.accounts a join public.journal_lines l on l.org_id=a.org_id and l.account_id=a.id
  join public.journal_entries e on e.org_id=l.org_id and e.id=l.entry_id
  where a.org_id=p_org and a.type in ('revenue','expense') and e.status in ('posted','reversed') and e.entry_date<p_from
    and e.entry_date>coalesce((select max(c.fiscal_year_end) from public.fiscal_year_closings c where c.org_id=p_org and c.fiscal_year_end<p_from
      and (c.status='posted' or (c.status='reversed' and c.reversal_date>=p_from))),date '-infinity')
    and e.entry_kind<>'closing' and not(e.entry_kind='reversal' and exists(select 1 from public.journal_entries source where source.org_id=e.org_id and source.id=e.reverses_id and source.entry_kind='closing'));
  select coalesce(sum(l.base_credit-l.base_debit),0) into closing_earnings
  from public.accounts a join public.journal_lines l on l.org_id=a.org_id and l.account_id=a.id
  join public.journal_entries e on e.org_id=l.org_id and e.id=l.entry_id
  where a.org_id=p_org and a.type in ('revenue','expense') and e.status in ('posted','reversed') and e.entry_date<=p_to
    and e.entry_date>coalesce((select max(c.fiscal_year_end) from public.fiscal_year_closings c where c.org_id=p_org and c.fiscal_year_end<=p_to
      and (c.status='posted' or (c.status='reversed' and c.reversal_date>p_to))),date '-infinity')
    and e.entry_kind<>'closing' and not(e.entry_kind='reversal' and exists(select 1 from public.journal_entries source where source.org_id=e.org_id and source.id=e.reverses_id and source.entry_kind='closing'));
  return query
  with equity_accounts as (
    select a.id,a.code,a.name,coalesce(sum(l.base_credit-l.base_debit) filter(where e.entry_date<p_from),0) opening,
      coalesce(sum(l.base_credit-l.base_debit) filter(where e.entry_date between p_from and p_to),0) movement,
      coalesce(sum(l.base_credit-l.base_debit) filter(where e.entry_date<=p_to),0) closing
    from public.accounts a left join public.journal_lines l on l.org_id=a.org_id and l.account_id=a.id
    left join public.journal_entries e on e.org_id=l.org_id and e.id=l.entry_id and e.status in ('posted','reversed') and e.entry_date<=p_to
    where a.org_id=p_org and a.type='equity' group by a.id,a.code,a.name
  )
  select 'equity_account'::text,ea.id,ea.code,ea.name,ea.opening::text,ea.movement::text,ea.closing::text from equity_accounts ea
  union all
  select 'undistributed_earnings'::text,null::uuid,null::text,'Undistributed earnings (unclosed P&L)',
    opening_earnings::text,(closing_earnings-opening_earnings)::text,closing_earnings::text
  order by 1,3 nulls last;
end;
$$;
revoke all on function public.statement_of_changes_in_equity_exact(uuid,date,date) from public,anon,authenticated;
grant execute on function public.statement_of_changes_in_equity_exact(uuid,date,date) to authenticated;

revoke all on function private.is_fiscal_year_end_period(uuid,date,date) from public,anon,authenticated;

create or replace function private.fiscal_year_close_lines(p_org uuid,p_start date,p_end date,p_retained uuid)
returns table(account_id uuid,debit numeric,credit numeric)
language sql stable security definer set search_path = ''
as $$
  with activity as (
    select a.id account_id,coalesce(sum(l.base_debit-l.base_credit),0)::numeric(30,4) net_debit
    from public.accounts a join public.journal_lines l on l.org_id=a.org_id and l.account_id=a.id
    join public.journal_entries e on e.org_id=l.org_id and e.id=l.entry_id
    where a.org_id=p_org and a.type in ('revenue','expense') and e.status in ('posted','reversed') and e.entry_date<=p_end
    group by a.id
  ), lines as (
    select x.account_id,greatest(-x.net_debit,0)::numeric(30,4) debit,greatest(x.net_debit,0)::numeric(30,4) credit
      from activity x where x.net_debit<>0
    union all
    select p_retained,greatest(sum(x.net_debit),0)::numeric(30,4),greatest(-sum(x.net_debit),0)::numeric(30,4)
      from activity x having sum(x.net_debit)<>0
  )
  select l.account_id,l.debit,l.credit from lines l where l.debit<>0 or l.credit<>0 order by l.account_id;
$$;

revoke all on function private.fiscal_year_close_lines(uuid,date,date,uuid) from public,anon,authenticated;

create or replace function public.create_fiscal_year_close_draft(p_org uuid,p_period uuid,p_retained_earnings_account uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare actor uuid:=auth.uid();p public.accounting_periods%rowtype;org public.organizations%rowtype;fy_start date;entry_id uuid;lines jsonb;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to close a fiscal year'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_org::text,4));
  select * into p from public.accounting_periods where org_id=p_org and id=p_period for update;
  if not found then raise exception 'Accounting period not found'; end if;
  if p.is_closed then raise exception 'Reopen the year-end period before preparing its closing journal'; end if;
  if not private.is_fiscal_year_end_period(p_org,p.start_date,p.end_date) then raise exception 'Choose the final accounting period of the financial year'; end if;
  if exists(select 1 from public.fiscal_year_closings c where c.org_id=p_org and c.fiscal_year_end=p.end_date and c.status not in ('reversed','voided')) then
    raise exception 'A closing workflow already exists for this fiscal year';
  end if;
  fy_start:=(p.end_date-interval '1 year'+interval '1 day')::date;
  if exists(select 1 from public.journal_entries e where e.org_id=p_org and e.entry_date between fy_start and p.end_date
    and e.status in ('submitted','pending_approval','approved')) then raise exception 'Resolve pending journal entries for the financial year first'; end if;
  perform private.assert_open_period(p_org,p.end_date);
  select * into org from public.organizations where id=p_org;
  if not exists(select 1 from public.accounts a where a.org_id=p_org and a.id=p_retained_earnings_account and a.is_active and a.type='equity') then
    raise exception 'Select an active retained earnings equity account';
  end if;
  select jsonb_agg(jsonb_build_object('account_id',x.account_id,'debit',x.debit::text,'credit',x.credit::text,'memo','Fiscal year closing · '||extract(year from p.end_date)::text) order by x.account_id)
    into lines from private.fiscal_year_close_lines(p_org,fy_start,p.end_date,p_retained_earnings_account) x;
  if lines is null then raise exception 'There is no posted income or expense activity to close'; end if;
  entry_id:=public.create_journal_entry_draft(p_org,p.end_date,'FY-CLOSE-'||extract(year from p.end_date)::text,
    'Fiscal year closing journal · '||fy_start::text||' to '||p.end_date::text,org.base_currency,1,'closing',lines);
  insert into public.fiscal_year_closings(org_id,period_id,fiscal_year_start,fiscal_year_end,retained_earnings_account_id,journal_entry_id,created_by)
    values(p_org,p.id,fy_start,p.end_date,p_retained_earnings_account,entry_id,actor);
  perform public.submit_journal_entry(entry_id);
  return entry_id;
end;
$$;

revoke all on function public.create_fiscal_year_close_draft(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.create_fiscal_year_close_draft(uuid,uuid,uuid) to authenticated;
