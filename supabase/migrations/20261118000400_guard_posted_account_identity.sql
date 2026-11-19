-- Keep historical financial statement classification stable once an account
-- has participated in a posted entry. Labels and hierarchy affect reporting,
-- while activation and descriptions remain manageable.
create or replace function private.guard_posted_account_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.code,new.name,new.type,new.parent_id) is distinct from
     (old.code,old.name,old.type,old.parent_id)
     and exists (
       select 1
       from public.journal_lines l
       join public.journal_entries e on e.id=l.entry_id and e.org_id=l.org_id
       where l.org_id=old.org_id
         and l.account_id=old.id
         and e.status in ('posted','reversed')
     ) then
    raise exception 'Account code, name, type, and parent are locked after posting activity';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_posted_account_identity() from public,anon,authenticated;
drop trigger if exists account_posted_identity_guard on public.accounts;
create trigger account_posted_identity_guard
  before update of code,name,type,parent_id on public.accounts
  for each row execute function private.guard_posted_account_identity();
