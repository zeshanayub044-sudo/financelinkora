-- Drafts may be incomplete or unbalanced. Database validation remains mandatory
-- before submission, approval, and posting through private.validate_journal_entry.

create or replace function public.create_journal_entry_draft(
  p_org uuid,p_entry_date date,p_reference text,p_description text,p_currency char(3),
  p_exchange_rate numeric,p_entry_kind text,p_lines jsonb
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  new_entry uuid;
  item jsonb;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then
    raise exception 'Not authorized to create journal entries';
  end if;
  if nullif(trim(p_description),'') is null then raise exception 'Description is required'; end if;
  if p_exchange_rate is null or p_exchange_rate<=0 then raise exception 'Exchange rate must be positive'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<1 then
    raise exception 'At least one journal line is required';
  end if;
  insert into public.journal_entries(org_id,entry_date,reference,description,currency,exchange_rate,created_by,entry_kind)
    values(p_org,p_entry_date,nullif(trim(p_reference),''),trim(p_description),p_currency,p_exchange_rate,actor,coalesce(p_entry_kind,'general'))
    returning id into new_entry;
  for item in select value from jsonb_array_elements(p_lines) loop
    insert into public.journal_lines(entry_id,org_id,account_id,debit,credit,memo)
      values(new_entry,p_org,(item->>'account_id')::uuid,
        coalesce(nullif(item->>'debit','')::numeric,0),
        coalesce(nullif(item->>'credit','')::numeric,0),
        nullif(trim(item->>'memo'),''));
  end loop;
  return new_entry;
end;
$$;

create or replace function public.update_journal_entry_draft(
  p_entry uuid,p_entry_date date,p_reference text,p_description text,p_lines jsonb
) returns void language plpgsql security definer set search_path = ''
as $$
declare
  e public.journal_entries%rowtype;
  actor uuid := auth.uid();
  item jsonb;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  select * into e from public.journal_entries where id=p_entry for update;
  if not found then raise exception 'Entry not found'; end if;
  if e.created_by is distinct from actor then raise exception 'Only the draft creator may edit this entry'; end if;
  if not private.has_role(e.org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then
    raise exception 'Not authorized to edit journal entries';
  end if;
  if e.status<>'draft' then raise exception 'Only draft entries can be edited'; end if;
  if nullif(trim(p_description),'') is null then raise exception 'Description is required'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<1 then
    raise exception 'At least one journal line is required';
  end if;

  update public.journal_entries
    set entry_date=p_entry_date,reference=nullif(trim(p_reference),''),description=trim(p_description)
    where id=p_entry;
  delete from public.journal_lines where entry_id=p_entry and org_id=e.org_id;
  for item in select value from jsonb_array_elements(p_lines) loop
    insert into public.journal_lines(entry_id,org_id,account_id,debit,credit,memo)
      values(p_entry,e.org_id,(item->>'account_id')::uuid,
        coalesce(nullif(item->>'debit','')::numeric,0),
        coalesce(nullif(item->>'credit','')::numeric,0),
        nullif(trim(item->>'memo'),''));
  end loop;
end;
$$;

revoke all on function public.update_journal_entry_draft(uuid,date,text,text,jsonb) from public,anon;
grant execute on function public.create_journal_entry_draft(uuid,date,text,text,char,numeric,text,jsonb) to authenticated;
grant execute on function public.update_journal_entry_draft(uuid,date,text,text,jsonb) to authenticated;
