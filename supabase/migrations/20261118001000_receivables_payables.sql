-- Receivables and payables stay subordinate to the double-entry journal.
-- Source documents and payments create journal drafts that still require the
-- existing maker-checker approval and database posting workflow.
alter table public.journal_entries
  drop constraint if exists journal_entries_entry_kind_check,
  add constraint journal_entries_entry_kind_check check (entry_kind in (
    'general','opening_balance','income','expense','payment','bank_transfer','reversal','closing',
    'sales_invoice','purchase_bill','customer_payment','supplier_payment'
  ));

create table public.financial_parties (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  party_type text not null check (party_type in ('customer','supplier')),
  name text not null check (length(trim(name)) between 2 and 200),
  email text check (email is null or length(email)<=254),
  phone text check (phone is null or length(phone)<=60),
  is_active boolean not null default true,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique (org_id,id)
);
create unique index financial_parties_org_type_name_idx on public.financial_parties(org_id,party_type,lower(name));

create table public.financial_documents (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  document_type text not null check (document_type in ('invoice','bill')),
  document_number text not null check (length(trim(document_number)) between 1 and 80),
  party_id uuid not null,
  control_account_id uuid not null,
  issue_date date not null,
  due_date date not null,
  status text not null default 'draft' check (status in ('draft','in_review','issued','void')),
  journal_entry_id uuid,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (due_date>=issue_date),
  unique (org_id,id),
  unique (org_id,document_type,document_number),
  unique (org_id,journal_entry_id),
  foreign key (org_id,party_id) references public.financial_parties(org_id,id) on delete restrict,
  foreign key (org_id,control_account_id) references public.accounts(org_id,id) on delete restrict,
  foreign key (org_id,journal_entry_id) references public.journal_entries(org_id,id) on delete restrict
);

create table public.financial_document_lines (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  document_id uuid not null,
  account_id uuid not null,
  description text not null check (length(trim(description)) between 1 and 500),
  amount numeric(20,4) not null check (amount>0 and amount::text not in ('NaN','Infinity','-Infinity')),
  created_at timestamptz not null default now(),
  unique (org_id,id),
  foreign key (org_id,document_id) references public.financial_documents(org_id,id) on delete cascade,
  foreign key (org_id,account_id) references public.accounts(org_id,id) on delete restrict
);

create table public.financial_document_payments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  document_id uuid not null,
  payment_date date not null,
  account_id uuid not null,
  amount numeric(20,4) not null check (amount>0 and amount::text not in ('NaN','Infinity','-Infinity')),
  reference text check (reference is null or length(reference)<=120),
  journal_entry_id uuid,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique (org_id,id),
  unique (org_id,journal_entry_id),
  foreign key (org_id,document_id) references public.financial_documents(org_id,id) on delete restrict,
  foreign key (org_id,account_id) references public.accounts(org_id,id) on delete restrict,
  foreign key (org_id,journal_entry_id) references public.journal_entries(org_id,id) on delete restrict
);

create index financial_documents_party_due_idx on public.financial_documents(org_id,party_id,due_date desc);
create index financial_documents_status_idx on public.financial_documents(org_id,status,issue_date desc);
create index financial_document_lines_document_idx on public.financial_document_lines(org_id,document_id);
create index financial_document_payments_document_idx on public.financial_document_payments(org_id,document_id,payment_date desc);

alter table public.financial_parties enable row level security;
alter table public.financial_documents enable row level security;
alter table public.financial_document_lines enable row level security;
alter table public.financial_document_payments enable row level security;

create policy financial_parties_read on public.financial_parties for select to authenticated
  using (private.has_role(org_id,array['owner','administrator','accountant','finance_manager','approver','auditor','viewer']::public.member_role[]));
create policy financial_documents_read on public.financial_documents for select to authenticated
  using (private.has_role(org_id,array['owner','administrator','accountant','finance_manager','approver','auditor','viewer']::public.member_role[]));
create policy financial_document_lines_read on public.financial_document_lines for select to authenticated
  using (private.has_role(org_id,array['owner','administrator','accountant','finance_manager','approver','auditor','viewer']::public.member_role[]));
create policy financial_document_payments_read on public.financial_document_payments for select to authenticated
  using (private.has_role(org_id,array['owner','administrator','accountant','finance_manager','approver','auditor','viewer']::public.member_role[]));
grant select on public.financial_parties,public.financial_documents,public.financial_document_lines,public.financial_document_payments to authenticated;
revoke all on public.financial_parties,public.financial_documents,public.financial_document_lines,public.financial_document_payments from anon;
revoke insert,update,delete on public.financial_parties,public.financial_documents,public.financial_document_lines,public.financial_document_payments from authenticated;

create trigger audit_financial_parties after insert or update or delete on public.financial_parties
  for each row execute function private.audit_row();
create trigger audit_financial_documents after insert or update or delete on public.financial_documents
  for each row execute function private.audit_row();
create trigger audit_financial_document_lines after insert or update or delete on public.financial_document_lines
  for each row execute function private.audit_row();
create trigger audit_financial_document_payments after insert or update or delete on public.financial_document_payments
  for each row execute function private.audit_row();

create or replace function public.create_financial_party(p_org uuid,p_party_type text,p_name text,p_email text default null,p_phone text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare actor uuid:=auth.uid();new_party uuid;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then
    raise exception 'Not authorized to manage customers or suppliers';
  end if;
  if p_party_type not in ('customer','supplier') then raise exception 'Choose customer or supplier'; end if;
  if nullif(trim(p_name),'') is null or length(trim(p_name))>200 then raise exception 'Enter a party name'; end if;
  if length(coalesce(p_email,''))>254 or length(coalesce(p_phone,''))>60 then raise exception 'Contact details are too long'; end if;
  insert into public.financial_parties(org_id,party_type,name,email,phone,created_by)
    values(p_org,p_party_type,trim(p_name),nullif(trim(p_email),''),nullif(trim(p_phone),''),actor)
    returning id into new_party;
  return new_party;
end;
$$;

create or replace function private.document_journal_lines(p_document uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare d public.financial_documents%rowtype;total numeric(30,4);lines jsonb;
begin
  select * into d from public.financial_documents where id=p_document;
  if not found then raise exception 'Financial document not found'; end if;
  if not exists(select 1 from public.organizations o where o.id=d.org_id and o.accounting_method='accrual') then
    raise exception 'Invoices and bills currently require accrual accounting; cash-basis document posting is not implemented';
  end if;
  if not exists(select 1 from public.financial_parties p where p.org_id=d.org_id and p.id=d.party_id and p.is_active
      and p.party_type=case when d.document_type='invoice' then 'customer' else 'supplier' end) then
    raise exception 'Source customer or supplier is no longer active';
  end if;
  if not exists(select 1 from public.accounts a where a.org_id=d.org_id and a.id=d.control_account_id and a.is_active
      and ((d.document_type='invoice' and a.type='asset' and a.reporting_class='receivable')
        or (d.document_type='bill' and a.type='liability' and a.reporting_class='payable'))) then
    raise exception 'Source receivable or payable account is no longer active';
  end if;
  if exists(select 1 from public.financial_document_lines l join public.accounts a on a.org_id=l.org_id and a.id=l.account_id
      where l.org_id=d.org_id and l.document_id=d.id and (not a.is_active or a.type<>case when d.document_type='invoice' then 'revenue' else 'expense' end)) then
    raise exception 'Source line uses an inactive or unsupported account';
  end if;
  select coalesce(sum(l.amount),0) into total from public.financial_document_lines l
    where l.org_id=d.org_id and l.document_id=d.id;
  if total<=0 then raise exception 'Add at least one positive document line'; end if;
  if d.document_type='invoice' then
    select jsonb_build_array(jsonb_build_object('account_id',d.control_account_id,'debit',total::text,'credit','0','memo','Accounts receivable'))
      || coalesce(jsonb_agg(jsonb_build_object('account_id',l.account_id,'debit','0','credit',l.amount::text,'memo',l.description) order by l.id),'[]'::jsonb)
      into lines from public.financial_document_lines l where l.org_id=d.org_id and l.document_id=d.id;
  else
    select coalesce(jsonb_agg(jsonb_build_object('account_id',l.account_id,'debit',l.amount::text,'credit','0','memo',l.description) order by l.id),'[]'::jsonb)
      || jsonb_build_array(jsonb_build_object('account_id',d.control_account_id,'debit','0','credit',total::text,'memo','Accounts payable'))
      into lines from public.financial_document_lines l where l.org_id=d.org_id and l.document_id=d.id;
  end if;
  return lines;
end;
$$;
revoke all on function private.document_journal_lines(uuid) from public,anon,authenticated;

create or replace function public.create_financial_document_draft(
  p_org uuid,p_document_type text,p_party uuid,p_document_number text,p_issue_date date,p_due_date date,
  p_control_account uuid,p_lines jsonb
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare actor uuid:=auth.uid();doc_id uuid;item jsonb;line_account uuid;line_amount numeric;line_description text;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then
    raise exception 'Not authorized to create receivables or payables';
  end if;
  if p_document_type not in ('invoice','bill') then raise exception 'Choose invoice or bill'; end if;
  if not exists(select 1 from public.organizations o where o.id=p_org and o.accounting_method='accrual') then
    raise exception 'Invoices and bills currently require accrual accounting; cash-basis document posting is not implemented';
  end if;
  if nullif(trim(p_document_number),'') is null or length(p_document_number)>80 then raise exception 'Document number is required'; end if;
  if p_issue_date is null or p_due_date is null or p_due_date<p_issue_date then raise exception 'Enter a valid document and due date'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<1 or jsonb_array_length(p_lines)>1000 then
    raise exception 'A document needs between 1 and 1000 lines';
  end if;
  if not exists(select 1 from public.financial_parties p where p.org_id=p_org and p.id=p_party and p.is_active
      and p.party_type=case when p_document_type='invoice' then 'customer' else 'supplier' end) then
    raise exception 'Choose an active customer or supplier of the matching type';
  end if;
  if not exists(select 1 from public.accounts a where a.org_id=p_org and a.id=p_control_account and a.is_active
      and ((p_document_type='invoice' and a.type='asset' and a.reporting_class='receivable')
        or (p_document_type='bill' and a.type='liability' and a.reporting_class='payable'))) then
    raise exception 'Choose an active receivable or payable control account';
  end if;
  insert into public.financial_documents(org_id,document_type,document_number,party_id,control_account_id,issue_date,due_date,created_by)
    values(p_org,p_document_type,trim(p_document_number),p_party,p_control_account,p_issue_date,p_due_date,actor) returning id into doc_id;
  for item in select value from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(item)<>'object' then raise exception 'Document lines must be objects'; end if;
    line_account:=(item->>'account_id')::uuid;
    line_amount:=(item->>'amount')::numeric;
    line_description:=nullif(trim(item->>'description'),'');
    if line_amount is null or line_amount<=0 or line_amount::text in ('NaN','Infinity','-Infinity') or line_amount<>round(line_amount,4) then
      raise exception 'Document lines need finite amounts greater than zero with at most four decimal places';
    end if;
    if line_description is null or length(line_description)>500 then raise exception 'Enter a line description'; end if;
    if not exists(select 1 from public.accounts a where a.org_id=p_org and a.id=line_account and a.is_active
        and a.type=case when p_document_type='invoice' then 'revenue' else 'expense' end) then
      raise exception 'Invoice lines require active revenue accounts; bill lines require active expense accounts';
    end if;
    insert into public.financial_document_lines(org_id,document_id,account_id,description,amount)
      values(p_org,doc_id,line_account,line_description,line_amount);
  end loop;
  return doc_id;
end;
$$;

create or replace function public.update_financial_document_draft(
  p_document uuid,p_party uuid,p_document_number text,p_issue_date date,p_due_date date,
  p_control_account uuid,p_lines jsonb
) returns void language plpgsql security definer set search_path = ''
as $$
declare d public.financial_documents%rowtype;actor uuid:=auth.uid();lines jsonb;line_item jsonb;line_account uuid;line_amount numeric;line_description text;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  select * into d from public.financial_documents where id=p_document for update;
  if not found then raise exception 'Financial document not found'; end if;
  if d.created_by<>actor then raise exception 'Only the draft creator may edit this document'; end if;
  if not private.has_role(d.org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to edit this document'; end if;
  if d.status<>'draft' then raise exception 'Only draft documents can be edited'; end if;
  if p_due_date is null or p_issue_date is null or p_due_date<p_issue_date then raise exception 'Enter a valid document and due date'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<1 or jsonb_array_length(p_lines)>1000 then raise exception 'A document needs between 1 and 1000 lines'; end if;
  if not exists(select 1 from public.financial_parties p where p.org_id=d.org_id and p.id=p_party and p.is_active
      and p.party_type=case when d.document_type='invoice' then 'customer' else 'supplier' end) then raise exception 'Choose an active party of the matching type'; end if;
  if nullif(trim(p_document_number),'') is null or length(p_document_number)>80 then raise exception 'Document number is required'; end if;
  if not exists(select 1 from public.accounts a where a.org_id=d.org_id and a.id=p_control_account and a.is_active
      and ((d.document_type='invoice' and a.type='asset' and a.reporting_class='receivable')
        or (d.document_type='bill' and a.type='liability' and a.reporting_class='payable'))) then raise exception 'Choose an active control account'; end if;
  delete from public.financial_document_lines where org_id=d.org_id and document_id=d.id;
  for line_item in select value from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(line_item)<>'object' then raise exception 'Document lines must be objects'; end if;
    line_account:=(line_item->>'account_id')::uuid;
    line_amount:=(line_item->>'amount')::numeric;
    line_description:=nullif(trim(line_item->>'description'),'');
    if line_amount is null or line_amount<=0 or line_amount::text in ('NaN','Infinity','-Infinity') or line_amount<>round(line_amount,4) then raise exception 'Document line amount is invalid'; end if;
    if line_description is null or length(line_description)>500 then raise exception 'Enter a line description'; end if;
    if not exists(select 1 from public.accounts a where a.org_id=d.org_id and a.id=line_account and a.is_active
        and a.type=case when d.document_type='invoice' then 'revenue' else 'expense' end) then raise exception 'Document line account has the wrong account type'; end if;
    insert into public.financial_document_lines(org_id,document_id,account_id,description,amount)
      values(d.org_id,d.id,line_account,line_description,line_amount);
  end loop;
  update public.financial_documents set party_id=p_party,document_number=trim(p_document_number),issue_date=p_issue_date,
    due_date=p_due_date,control_account_id=p_control_account,updated_at=now() where id=d.id;
  if d.journal_entry_id is not null then
    lines:=private.document_journal_lines(d.id);
    perform public.update_journal_entry_draft(d.journal_entry_id,p_issue_date,trim(p_document_number),'Document '||trim(p_document_number),lines);
  end if;
end;
$$;

create or replace function public.submit_financial_document(p_document uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare d public.financial_documents%rowtype;actor uuid:=auth.uid();org_currency char(3);journal_id uuid;lines jsonb;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  select * into d from public.financial_documents where id=p_document for update;
  if not found then raise exception 'Financial document not found'; end if;
  if d.created_by<>actor then raise exception 'Only the creator may submit this document'; end if;
  if not private.has_role(d.org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to submit this document'; end if;
  if d.status<>'draft' then raise exception 'Only draft documents can be submitted'; end if;
  if not exists(select 1 from public.organizations o where o.id=d.org_id and o.accounting_method='accrual') then
    raise exception 'Invoices and bills currently require accrual accounting';
  end if;
  perform private.assert_open_period(d.org_id,d.issue_date);
  lines:=private.document_journal_lines(d.id);
  select base_currency into org_currency from public.organizations where id=d.org_id;
  if d.journal_entry_id is null then
    journal_id:=public.create_journal_entry_draft(d.org_id,d.issue_date,d.document_number,
      initcap(d.document_type)||' '||d.document_number,org_currency,1,
      case when d.document_type='invoice' then 'sales_invoice' else 'purchase_bill' end,lines);
  else
    journal_id:=d.journal_entry_id;
    perform public.update_journal_entry_draft(journal_id,d.issue_date,d.document_number,
      initcap(d.document_type)||' '||d.document_number,lines);
  end if;
  update public.financial_documents set journal_entry_id=journal_id,status='in_review',updated_at=now() where id=d.id;
  perform public.submit_journal_entry(journal_id);
  return journal_id;
end;
$$;

create or replace function public.record_financial_document_payment(
  p_document uuid,p_payment_date date,p_account uuid,p_amount numeric,p_reference text default null
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  d public.financial_documents%rowtype;actor uuid:=auth.uid();
  amount_reserved numeric(30,4);document_total numeric(30,4);org_currency char(3);
  new_payment uuid;journal_id uuid;payment_lines jsonb;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  select * into d from public.financial_documents where id=p_document for update;
  if not found then raise exception 'Financial document not found'; end if;
  if not private.has_role(d.org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to record payments'; end if;
  if d.status<>'issued' then raise exception 'Payments require an issued invoice or bill'; end if;
  if p_payment_date is null then raise exception 'Payment date is required'; end if;
  perform private.assert_open_period(d.org_id,p_payment_date);
  if p_amount is null or p_amount<=0 or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<>round(p_amount,4) then
    raise exception 'Payment amount must be finite, positive, and have at most four decimal places';
  end if;
  if length(coalesce(p_reference,''))>120 then raise exception 'Payment reference is too long'; end if;
  if not exists(select 1 from public.accounts a where a.org_id=d.org_id and a.id=p_account and a.is_active and a.type='asset' and a.reporting_class in ('cash','bank')) then
    raise exception 'Choose an active cash or bank account';
  end if;
  select coalesce(sum(l.amount),0) into document_total from public.financial_document_lines l where l.org_id=d.org_id and l.document_id=d.id;
  select coalesce(sum(p.amount),0) into amount_reserved
    from public.financial_document_payments p join public.journal_entries e on e.org_id=p.org_id and e.id=p.journal_entry_id
    where p.org_id=d.org_id and p.document_id=d.id and e.status in ('submitted','pending_approval','approved','posted');
  if p_amount+amount_reserved>document_total then raise exception 'Payment exceeds the unpaid document balance'; end if;

  insert into public.financial_document_payments(org_id,document_id,payment_date,account_id,amount,reference,created_by)
    values(d.org_id,d.id,p_payment_date,p_account,p_amount,nullif(trim(p_reference),''),actor) returning id into new_payment;
  if d.document_type='invoice' then
    payment_lines:=jsonb_build_array(
      jsonb_build_object('account_id',p_account,'debit',p_amount::text,'credit','0','memo','Customer receipt'),
      jsonb_build_object('account_id',d.control_account_id,'debit','0','credit',p_amount::text,'memo','Reduce accounts receivable')
    );
  else
    payment_lines:=jsonb_build_array(
      jsonb_build_object('account_id',d.control_account_id,'debit',p_amount::text,'credit','0','memo','Reduce accounts payable'),
      jsonb_build_object('account_id',p_account,'debit','0','credit',p_amount::text,'memo','Supplier payment')
    );
  end if;
  select base_currency into org_currency from public.organizations where id=d.org_id;
  journal_id:=public.create_journal_entry_draft(d.org_id,p_payment_date,nullif(trim(p_reference),''),
    'Payment for '||d.document_number,org_currency,1,
    case when d.document_type='invoice' then 'customer_payment' else 'supplier_payment' end,payment_lines);
  update public.financial_document_payments set journal_entry_id=journal_id where id=new_payment;
  perform public.submit_journal_entry(journal_id);
  return journal_id;
end;
$$;

create or replace function public.resubmit_financial_document_payment(p_payment uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  payment public.financial_document_payments%rowtype;
  d public.financial_documents%rowtype;
  actor uuid:=auth.uid();
  document_id uuid;
  amount_reserved numeric(30,4);
  document_total numeric(30,4);
  lines jsonb;
  journal_state public.entry_status;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  select pay.document_id into document_id from public.financial_document_payments pay where pay.id=p_payment;
  if not found then raise exception 'Payment not found'; end if;
  select * into d from public.financial_documents where id=document_id for update;
  if not found then raise exception 'Financial document not found'; end if;
  select * into payment from public.financial_document_payments where id=p_payment and org_id=d.org_id for update;
  if not found then raise exception 'Payment not found'; end if;
  if payment.created_by<>actor then raise exception 'Only the payment creator may resubmit it'; end if;
  if not private.has_role(d.org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to resubmit this payment'; end if;
  if d.status<>'issued' or payment.journal_entry_id is null then raise exception 'Payment is not eligible for resubmission'; end if;
  select status into journal_state from public.journal_entries where org_id=d.org_id and id=payment.journal_entry_id for update;
  if not found or journal_state<>'draft' then raise exception 'Only a rejected payment draft can be resubmitted'; end if;
  if not exists(select 1 from public.accounts a where a.org_id=d.org_id and a.id=payment.account_id and a.is_active and a.type='asset' and a.reporting_class in ('cash','bank')) then
    raise exception 'The payment cash or bank account is no longer active';
  end if;
  select coalesce(sum(l.amount),0) into document_total from public.financial_document_lines l where l.org_id=d.org_id and l.document_id=d.id;
  select coalesce(sum(p.amount),0) into amount_reserved
    from public.financial_document_payments p join public.journal_entries e on e.org_id=p.org_id and e.id=p.journal_entry_id
    where p.org_id=d.org_id and p.document_id=d.id and p.id<>payment.id and e.status in ('submitted','pending_approval','approved','posted');
  if payment.amount+amount_reserved>document_total then raise exception 'Payment now exceeds the unpaid document balance'; end if;
  if d.document_type='invoice' then
    lines:=jsonb_build_array(
      jsonb_build_object('account_id',payment.account_id,'debit',payment.amount::text,'credit','0','memo','Customer receipt'),
      jsonb_build_object('account_id',d.control_account_id,'debit','0','credit',payment.amount::text,'memo','Reduce accounts receivable')
    );
  else
    lines:=jsonb_build_array(
      jsonb_build_object('account_id',d.control_account_id,'debit',payment.amount::text,'credit','0','memo','Reduce accounts payable'),
      jsonb_build_object('account_id',payment.account_id,'debit','0','credit',payment.amount::text,'memo','Supplier payment')
    );
  end if;
  perform public.update_journal_entry_draft(payment.journal_entry_id,payment.payment_date,payment.reference,
    'Payment for '||d.document_number,lines);
  perform public.submit_journal_entry(payment.journal_entry_id);
  return payment.journal_entry_id;
end;
$$;

create or replace function private.guard_financial_document_entry()
returns trigger language plpgsql set search_path = ''
as $$
declare
  d public.financial_documents%rowtype;
  p public.financial_document_payments%rowtype;
  expected jsonb;
begin
  if new.status is not distinct from old.status then return new; end if;
  if new.status='reversed' and new.entry_kind in ('sales_invoice','purchase_bill') then
    if exists(select 1 from public.financial_document_payments p join public.journal_entries e on e.org_id=p.org_id and e.id=p.journal_entry_id
        where p.org_id=new.org_id and p.document_id=(select d.id from public.financial_documents d where d.org_id=new.org_id and d.journal_entry_id=new.id)
          and e.status in ('submitted','pending_approval','approved','posted')) then
      raise exception 'An invoice or bill with active payments cannot be reversed';
    end if;
    return new;
  end if;
  if new.status not in ('submitted','pending_approval','approved','posted') then return new; end if;
  if new.entry_kind in ('sales_invoice','purchase_bill') then
    select * into d from public.financial_documents where org_id=new.org_id and journal_entry_id=new.id for update;
    if not found then raise exception 'Invoice or bill journal entry must be linked to its source document'; end if;
    if d.status not in ('in_review','issued') then raise exception 'Source invoice or bill is not awaiting posting'; end if;
    if d.created_by<>new.created_by or d.org_id<>new.org_id
       or (d.document_type='invoice' and new.entry_kind<>'sales_invoice')
       or (d.document_type='bill' and new.entry_kind<>'purchase_bill') then
      raise exception 'Source document does not match the journal entry';
    end if;
    expected:=private.document_journal_lines(d.id);
  elsif new.entry_kind in ('customer_payment','supplier_payment') then
    select * into p from public.financial_document_payments where org_id=new.org_id and journal_entry_id=new.id for update;
    if not found then raise exception 'Payment journal entry must be linked to its source payment'; end if;
    select doc.* into d from public.financial_documents doc where doc.org_id=p.org_id and doc.id=p.document_id;
    if not found then raise exception 'Payment source document not found'; end if;
    if d.status<>'issued' then raise exception 'Payments can only be posted for an issued invoice or bill'; end if;
    if (new.entry_kind='customer_payment' and d.document_type<>'invoice')
       or (new.entry_kind='supplier_payment' and d.document_type<>'bill') then
      raise exception 'Payment journal kind does not match its source document';
    end if;
    if not exists(select 1 from public.accounts a where a.org_id=p.org_id and a.id=p.account_id and a.is_active
        and a.type='asset' and a.reporting_class in ('cash','bank')) then
      raise exception 'Payment source must be an active cash or bank account';
    end if;
    if new.entry_kind='customer_payment' then
      expected:=jsonb_build_array(
        jsonb_build_object('account_id',p.account_id,'debit',p.amount::text,'credit','0'),
        jsonb_build_object('account_id',d.control_account_id,'debit','0','credit',p.amount::text)
      );
    else
      expected:=jsonb_build_array(
        jsonb_build_object('account_id',d.control_account_id,'debit',p.amount::text,'credit','0'),
        jsonb_build_object('account_id',p.account_id,'debit','0','credit',p.amount::text)
      );
    end if;
  else return new;
  end if;
  if exists(
    (select l.account_id,l.debit,l.credit from public.journal_lines l where l.org_id=new.org_id and l.entry_id=new.id
     except all
     select (line->>'account_id')::uuid,coalesce((line->>'debit')::numeric,0),coalesce((line->>'credit')::numeric,0) from jsonb_array_elements(expected) as x(line))
    union all
    (select (line->>'account_id')::uuid,coalesce((line->>'debit')::numeric,0),coalesce((line->>'credit')::numeric,0) from jsonb_array_elements(expected) as x(line)
     except all
     select l.account_id,l.debit,l.credit from public.journal_lines l where l.org_id=new.org_id and l.entry_id=new.id)
  ) then raise exception 'Source document or payment journal lines differ from the linked source'; end if;
  return new;
end;
$$;
revoke all on function private.guard_financial_document_entry() from public,anon,authenticated;
drop trigger if exists guard_financial_document_entry on public.journal_entries;
create trigger guard_financial_document_entry before update of status on public.journal_entries
  for each row execute function private.guard_financial_document_entry();

create or replace function private.sync_financial_document_status()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if old.status is distinct from new.status and new.entry_kind in ('sales_invoice','purchase_bill') then
    if new.status='posted' then
      update public.financial_documents set status='issued',updated_at=now() where org_id=new.org_id and journal_entry_id=new.id;
    elsif new.status='draft' and new.rejection_reason is not null then
      update public.financial_documents set status='draft',updated_at=now() where org_id=new.org_id and journal_entry_id=new.id and status='in_review';
    elsif new.status='reversed' then
      update public.financial_documents set status='void',updated_at=now() where org_id=new.org_id and journal_entry_id=new.id and status='issued';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.sync_financial_document_status() from public,anon,authenticated;
drop trigger if exists sync_financial_document_status on public.journal_entries;
create trigger sync_financial_document_status after update of status on public.journal_entries
  for each row execute function private.sync_financial_document_status();

create or replace view public.financial_documents_exact with (security_invoker=true) as
select d.id,d.org_id,d.document_type,d.document_number,d.party_id,p.name party_name,d.control_account_id,
  d.issue_date,d.due_date,d.status journal_status,d.journal_entry_id,d.created_by,d.created_at,
  coalesce((select sum(l.amount) from public.financial_document_lines l where l.org_id=d.org_id and l.document_id=d.id),0)::text total,
  coalesce((select sum(pay.amount) from public.financial_document_payments pay join public.journal_entries e
    on e.org_id=pay.org_id and e.id=pay.journal_entry_id and e.status='posted'
    where pay.org_id=d.org_id and pay.document_id=d.id),0)::text paid,
  (coalesce((select sum(l.amount) from public.financial_document_lines l where l.org_id=d.org_id and l.document_id=d.id),0)
    -coalesce((select sum(pay.amount) from public.financial_document_payments pay join public.journal_entries e
      on e.org_id=pay.org_id and e.id=pay.journal_entry_id and e.status='posted'
      where pay.org_id=d.org_id and pay.document_id=d.id),0))::text outstanding,
  case when d.status<>'issued' then d.status
    when coalesce((select sum(pay.amount) from public.financial_document_payments pay join public.journal_entries e
      on e.org_id=pay.org_id and e.id=pay.journal_entry_id and e.status='posted'
      where pay.org_id=d.org_id and pay.document_id=d.id),0)=0 then 'issued'
    when coalesce((select sum(pay.amount) from public.financial_document_payments pay join public.journal_entries e
      on e.org_id=pay.org_id and e.id=pay.journal_entry_id and e.status='posted'
      where pay.org_id=d.org_id and pay.document_id=d.id),0)
      >=coalesce((select sum(l.amount) from public.financial_document_lines l where l.org_id=d.org_id and l.document_id=d.id),0) then 'paid'
    else 'partially_paid' end as collection_status
from public.financial_documents d join public.financial_parties p on p.org_id=d.org_id and p.id=d.party_id;

revoke all on public.financial_documents_exact from public,anon,authenticated;
grant select on public.financial_documents_exact to authenticated;

create or replace function public.financial_aging_exact(p_org uuid,p_as_of date default current_date)
returns table(
  document_id uuid,org_id uuid,document_type text,document_number text,party_id uuid,party_name text,
  issue_date date,due_date date,days_past_due integer,outstanding text,aging_bucket text
) language sql stable security invoker set search_path = ''
as $$
  select d.id,d.org_id,d.document_type,d.document_number,d.party_id,d.party_name,d.issue_date,d.due_date,
    greatest(0,coalesce(p_as_of,current_date)-d.due_date)::integer,d.outstanding,
    case when d.due_date>=coalesce(p_as_of,current_date) then 'current'
      when coalesce(p_as_of,current_date)-d.due_date<=30 then '1_30_days'
      when coalesce(p_as_of,current_date)-d.due_date<=60 then '31_60_days'
      when coalesce(p_as_of,current_date)-d.due_date<=90 then '61_90_days'
      else 'over_90_days' end
  from public.financial_documents_exact d
  where d.org_id=p_org and d.journal_status='issued' and d.outstanding::numeric>0
  order by d.due_date,d.document_number
$$;
revoke all on function public.financial_aging_exact(uuid,date) from public,anon,authenticated;
grant execute on function public.financial_aging_exact(uuid,date) to authenticated;

revoke all on function public.create_financial_party(uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.create_financial_document_draft(uuid,text,uuid,text,date,date,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.update_financial_document_draft(uuid,uuid,text,date,date,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.submit_financial_document(uuid) from public,anon,authenticated;
revoke all on function public.record_financial_document_payment(uuid,date,uuid,numeric,text) from public,anon,authenticated;
revoke all on function public.resubmit_financial_document_payment(uuid) from public,anon,authenticated;
grant execute on function public.create_financial_party(uuid,text,text,text,text) to authenticated;
grant execute on function public.create_financial_document_draft(uuid,text,uuid,text,date,date,uuid,jsonb) to authenticated;
grant execute on function public.update_financial_document_draft(uuid,uuid,text,date,date,uuid,jsonb) to authenticated;
grant execute on function public.submit_financial_document(uuid) to authenticated;
grant execute on function public.record_financial_document_payment(uuid,date,uuid,numeric,text) to authenticated;
grant execute on function public.resubmit_financial_document_payment(uuid) to authenticated;
