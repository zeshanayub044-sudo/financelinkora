-- Resolve the PL/pgSQL variable/table alias ambiguity in the posting guard.
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
  elsif new.status='posted' and exists(select 1 from public.fiscal_year_closings pending_close where pending_close.org_id=new.org_id and pending_close.status='submitted'
    and new.entry_date between pending_close.fiscal_year_start and pending_close.fiscal_year_end) then
    raise exception 'A fiscal-year close is awaiting posting; complete or reject it before posting other entries in that year';
  end if;
  return new;
end;
$$;
revoke all on function private.guard_fiscal_year_close() from public,anon,authenticated;
