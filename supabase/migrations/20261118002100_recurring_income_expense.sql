-- Recurring plans are templates only. A member explicitly generates each due
-- journal draft; ordinary maker-checker approval and posting still apply.
create table public.recurring_templates (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check(length(trim(name)) between 2 and 200),
  transaction_kind text not null check(transaction_kind in ('income','expense')),
  frequency text not null check(frequency in ('monthly','quarterly','annually')),
  start_date date not null,
  end_date date,
  next_date date not null,
  amount numeric(20,4) not null check(amount>0 and amount::text not in ('NaN','Infinity','-Infinity')),
  category_account_id uuid not null,
  asset_account_id uuid not null,
  description text not null check(length(trim(description)) between 2 and 500),
  reference_prefix text not null default '' check(length(reference_prefix)<=100),
  is_active boolean not null default true,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique(org_id,id),
  foreign key(org_id,category_account_id) references public.accounts(org_id,id) on delete restrict,
  foreign key(org_id,asset_account_id) references public.accounts(org_id,id) on delete restrict,
  check(end_date is null or end_date>=start_date),
  check(next_date>=start_date),
  check(category_account_id<>asset_account_id)
);
create table public.recurring_occurrences (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  template_id uuid not null,
  scheduled_date date not null,
  journal_entry_id uuid not null,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique(org_id,id),
  unique(org_id,template_id,scheduled_date),
  unique(org_id,journal_entry_id),
  foreign key(org_id,template_id) references public.recurring_templates(org_id,id) on delete restrict,
  foreign key(org_id,journal_entry_id) references public.journal_entries(org_id,id) on delete restrict
);
create index recurring_templates_due_idx on public.recurring_templates(org_id,is_active,next_date);
create index recurring_occurrences_template_idx on public.recurring_occurrences(org_id,template_id,scheduled_date desc);
alter table public.recurring_templates enable row level security;
alter table public.recurring_occurrences enable row level security;
create policy recurring_templates_read on public.recurring_templates for select to authenticated
  using(private.has_role(org_id,array['owner','administrator','finance_manager','accountant','approver','auditor','viewer']::public.member_role[]));
create policy recurring_occurrences_read on public.recurring_occurrences for select to authenticated
  using(private.has_role(org_id,array['owner','administrator','finance_manager','accountant','approver','auditor','viewer']::public.member_role[]));
grant select on public.recurring_templates,public.recurring_occurrences to authenticated;
revoke all on public.recurring_templates,public.recurring_occurrences from anon;
revoke insert,update,delete on public.recurring_templates,public.recurring_occurrences from authenticated;
create trigger audit_recurring_templates after insert or update or delete on public.recurring_templates for each row execute function private.audit_row();
create trigger audit_recurring_occurrences after insert or update or delete on public.recurring_occurrences for each row execute function private.audit_row();

create or replace function public.create_recurring_template(
  p_org uuid,p_name text,p_kind text,p_frequency text,p_start date,p_end date,
  p_amount numeric,p_category_account uuid,p_asset_account uuid,p_description text,p_reference_prefix text default ''
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare actor uuid:=auth.uid();new_id uuid;expected public.account_type;asset_account public.accounts%rowtype;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','finance_manager','accountant']::public.member_role[]) then raise exception 'Not authorized to manage recurring templates'; end if;
  if nullif(trim(p_name),'') is null or length(trim(p_name))>200 or nullif(trim(p_description),'') is null or length(trim(p_description))>500 then raise exception 'Enter a template name and description'; end if;
  if p_kind not in ('income','expense') then raise exception 'Choose income or expense'; end if;
  if p_frequency not in ('monthly','quarterly','annually') then raise exception 'Choose monthly, quarterly, or annual frequency'; end if;
  if p_start is null or (p_end is not null and p_end<p_start) then raise exception 'Enter a valid schedule date range'; end if;
  if p_amount is null or p_amount<=0 or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<>round(p_amount,4) then raise exception 'Amount must be positive with up to four decimal places'; end if;
  if length(coalesce(p_reference_prefix,''))>100 then raise exception 'Reference prefix must be at most 100 characters'; end if;
  expected:=case when p_kind='income' then 'revenue'::public.account_type else 'expense'::public.account_type end;
  if not exists(select 1 from public.accounts a where a.org_id=p_org and a.id=p_category_account and a.is_active and a.type=expected) then raise exception 'Choose an active account matching the transaction type'; end if;
  select * into asset_account from public.accounts a where a.org_id=p_org and a.id=p_asset_account and a.is_active and a.type='asset' and a.reporting_class in ('cash','bank');
  if not found then raise exception 'Choose an active cash or bank account'; end if;
  insert into public.recurring_templates(org_id,name,transaction_kind,frequency,start_date,end_date,next_date,amount,category_account_id,asset_account_id,description,reference_prefix,created_by)
    values(p_org,trim(p_name),p_kind,p_frequency,p_start,p_end,p_start,p_amount,p_category_account,p_asset_account,trim(p_description),coalesce(trim(p_reference_prefix),''),actor)
    returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.set_recurring_template_active(p_org uuid,p_template uuid,p_active boolean)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','finance_manager','accountant']::public.member_role[]) then raise exception 'Not authorized to manage recurring templates'; end if;
  update public.recurring_templates set is_active=p_active where org_id=p_org and id=p_template;
  if not found then raise exception 'Recurring template not found'; end if;
end;
$$;

create or replace function public.generate_recurring_journal_draft(p_org uuid,p_template uuid,p_scheduled_date date)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare t public.recurring_templates%rowtype;actor uuid:=auth.uid();existing uuid;months integer;step integer;currency char(3);entry_id uuid;reference text;lines jsonb;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  select * into t from public.recurring_templates where org_id=p_org and id=p_template for update;
  if not found then raise exception 'Recurring template not found'; end if;
  if not private.has_role(t.org_id,array['owner','administrator','finance_manager','accountant']::public.member_role[]) then raise exception 'Not authorized to generate recurring entries'; end if;
  if not t.is_active then raise exception 'Recurring template is inactive'; end if;
  if p_scheduled_date is null or p_scheduled_date<>t.next_date or (t.end_date is not null and p_scheduled_date>t.end_date) then raise exception 'Only the next scheduled date can be generated'; end if;
  step:=case t.frequency when 'monthly' then 1 when 'quarterly' then 3 else 12 end;
  months:=(extract(year from p_scheduled_date)::integer-extract(year from t.start_date)::integer)*12+extract(month from p_scheduled_date)::integer-extract(month from t.start_date)::integer;
  if months<0 or months%step<>0 or (t.start_date+make_interval(months=>months))::date<>p_scheduled_date then raise exception 'Date does not match the template frequency'; end if;
  perform private.assert_open_period(t.org_id,p_scheduled_date);
  select journal_entry_id into existing from public.recurring_occurrences where org_id=t.org_id and template_id=t.id and scheduled_date=p_scheduled_date;
  if existing is not null then return existing; end if;
  if not exists(select 1 from public.accounts where org_id=t.org_id and id=t.category_account_id and is_active and type=case when t.transaction_kind='income' then 'revenue'::public.account_type else 'expense'::public.account_type end)
    or not exists(select 1 from public.accounts where org_id=t.org_id and id=t.asset_account_id and is_active and type='asset' and reporting_class in ('cash','bank')) then raise exception 'Template accounts must remain active and correctly classified'; end if;
  select base_currency into currency from public.organizations where id=t.org_id;
  reference:=nullif(concat_ws('-',nullif(t.reference_prefix,''),to_char(p_scheduled_date,'YYYYMMDD')),'');
  lines:=case when t.transaction_kind='income' then
    jsonb_build_array(jsonb_build_object('account_id',t.asset_account_id,'debit',t.amount::text,'credit','0'),jsonb_build_object('account_id',t.category_account_id,'debit','0','credit',t.amount::text))
    else jsonb_build_array(jsonb_build_object('account_id',t.category_account_id,'debit',t.amount::text,'credit','0'),jsonb_build_object('account_id',t.asset_account_id,'debit','0','credit',t.amount::text)) end;
  entry_id:=public.create_journal_entry_draft(t.org_id,p_scheduled_date,reference,t.description,currency,1,t.transaction_kind,lines);
  insert into public.recurring_occurrences(org_id,template_id,scheduled_date,journal_entry_id,created_by) values(t.org_id,t.id,p_scheduled_date,entry_id,actor);
  update public.recurring_templates set next_date=(start_date+make_interval(months=>months+step))::date,
    is_active=case when end_date is not null and (start_date+make_interval(months=>months+step))::date>end_date then false else is_active end
    where org_id=t.org_id and id=t.id;
  return entry_id;
end;
$$;
revoke all on function public.create_recurring_template(uuid,text,text,text,date,date,numeric,uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.set_recurring_template_active(uuid,uuid,boolean) from public,anon,authenticated;
revoke all on function public.generate_recurring_journal_draft(uuid,uuid,date) from public,anon,authenticated;
grant execute on function public.create_recurring_template(uuid,text,text,text,date,date,numeric,uuid,uuid,text,text) to authenticated;
grant execute on function public.set_recurring_template_active(uuid,uuid,boolean) to authenticated;
grant execute on function public.generate_recurring_journal_draft(uuid,uuid,date) to authenticated;
