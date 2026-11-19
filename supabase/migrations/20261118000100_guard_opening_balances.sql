-- Opening balances affect balance sheet accounts only. Their submission,
-- approval, and posting is restricted to organization owners and finance managers.
create or replace function public.trg_opening_balance_guard()
returns trigger language plpgsql set search_path = ''
as $$
declare
  affected_lines bigint;
begin
  if new.entry_kind <> 'opening_balance' then return new; end if;

  if tg_op='INSERT' and not private.has_role(new.org_id,array['owner','finance_manager']::public.member_role[]) then
    raise exception 'Only an owner or finance manager may create an opening balance entry';
  end if;

  if tg_op='UPDATE' and new.status is distinct from old.status
     and new.status in ('submitted','pending_approval','approved','posted') then
    select count(*) into affected_lines
      from public.journal_lines l
      join public.accounts a on a.id=l.account_id and a.org_id=l.org_id
      where l.entry_id=new.id and l.org_id=new.org_id;

    if affected_lines<2 then raise exception 'Opening balances need at least two lines'; end if;
    if exists(
      select 1 from public.journal_lines l
      join public.accounts a on a.id=l.account_id and a.org_id=l.org_id
      where l.entry_id=new.id and l.org_id=new.org_id
        and a.type not in ('asset','liability','equity')
    ) then raise exception 'Opening balances may only use asset, liability, and equity accounts'; end if;
  end if;
  return new;
end;
$$;

revoke all on function public.trg_opening_balance_guard() from public,anon,authenticated;
drop trigger if exists opening_balance_guard on public.journal_entries;
create trigger opening_balance_guard
  before insert or update of entry_kind,status on public.journal_entries
  for each row execute function public.trg_opening_balance_guard();
