-- Configurable tax setup and tax-exclusive invoice/bill calculations.
-- No jurisdiction or statutory rate is assumed. Values are snapshotted on lines.
create table public.tax_codes (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9._-]{0,39}$'),
  name text not null check (length(trim(name)) between 2 and 200),
  scope text not null check (scope in ('sales','purchases','both')),
  rate numeric(9,6) not null check (rate>=0 and rate<=100 and rate::text not in ('NaN','Infinity','-Infinity')),
  sales_account_id uuid,
  purchase_account_id uuid,
  effective_from date not null,
  effective_to date,
  is_active boolean not null default true,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  check (effective_to is null or effective_to>=effective_from),
  unique(org_id,id),unique(org_id,code),
  foreign key(org_id,sales_account_id) references public.accounts(org_id,id) on delete restrict,
  foreign key(org_id,purchase_account_id) references public.accounts(org_id,id) on delete restrict
);
create index tax_codes_org_active_idx on public.tax_codes(org_id,is_active,code);

alter table public.financial_document_lines
  add column tax_code_id uuid,
  add column tax_rate numeric(9,6) not null default 0,
  add column tax_amount numeric(20,4) not null default 0,
  add column tax_account_id uuid,
  add constraint financial_document_lines_tax_rate_check check (tax_rate>=0 and tax_rate<=100 and tax_rate::text not in ('NaN','Infinity','-Infinity')),
  add constraint financial_document_lines_tax_amount_check check (tax_amount>=0 and tax_amount::text not in ('NaN','Infinity','-Infinity')),
  add constraint financial_document_lines_tax_code_fk foreign key(org_id,tax_code_id) references public.tax_codes(org_id,id) on delete restrict,
  add constraint financial_document_lines_tax_account_fk foreign key(org_id,tax_account_id) references public.accounts(org_id,id) on delete restrict,
  add constraint financial_document_lines_tax_code_presence_check check (
    tax_code_id is not null or (tax_rate=0 and tax_amount=0 and tax_account_id is null)
  );
create index financial_document_lines_tax_code_idx on public.financial_document_lines(org_id,tax_code_id) where tax_code_id is not null;

alter table public.tax_codes enable row level security;
create policy tax_codes_read on public.tax_codes for select to authenticated
  using(private.has_role(org_id,array['owner','administrator','accountant','finance_manager','approver','auditor','viewer']::public.member_role[]));
grant select on public.tax_codes to authenticated;
revoke insert,update,delete on public.tax_codes from authenticated;
revoke all on public.tax_codes from anon;
create trigger audit_tax_codes after insert or update or delete on public.tax_codes
  for each row execute function private.audit_row();

create or replace function public.create_tax_code(
  p_org uuid,p_code text,p_name text,p_scope text,p_rate numeric,
  p_sales_account uuid,p_purchase_account uuid,p_effective_from date,p_effective_to date default null
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare actor uuid:=auth.uid();new_id uuid;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','finance_manager','accountant']::public.member_role[]) then raise exception 'Not authorized to manage tax codes'; end if;
  if nullif(trim(p_code),'') is null or length(trim(p_code))>40 or trim(p_code)!~'^[A-Za-z0-9][A-Za-z0-9._-]*$' then raise exception 'Enter a valid tax code'; end if;
  if nullif(trim(p_name),'') is null or length(trim(p_name))>200 then raise exception 'Enter a valid tax name'; end if;
  if p_scope not in ('sales','purchases','both') then raise exception 'Choose sales, purchases, or both'; end if;
  if p_rate is null or p_rate<0 or p_rate>100 or p_rate::text in ('NaN','Infinity','-Infinity') or p_rate<>round(p_rate,6) then raise exception 'Tax rate must be between 0 and 100 with at most six decimal places'; end if;
  if p_effective_from is null or (p_effective_to is not null and p_effective_to<p_effective_from) then raise exception 'Choose a valid effective date range'; end if;
  if p_rate>0 and p_scope in ('sales','both') and not exists(select 1 from public.accounts a where a.org_id=p_org and a.id=p_sales_account and a.is_active and a.type='liability') then raise exception 'Taxable sales require an active tax liability account'; end if;
  if p_rate>0 and p_scope in ('purchases','both') and not exists(select 1 from public.accounts a where a.org_id=p_org and a.id=p_purchase_account and a.is_active and a.type='asset') then raise exception 'Taxable purchases require an active recoverable tax asset account'; end if;
  insert into public.tax_codes(org_id,code,name,scope,rate,sales_account_id,purchase_account_id,effective_from,effective_to,created_by)
    values(p_org,upper(trim(p_code)),trim(p_name),p_scope,p_rate,
      case when p_scope in ('sales','both') then p_sales_account end,
      case when p_scope in ('purchases','both') then p_purchase_account end,
      p_effective_from,p_effective_to,actor) returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.set_tax_code_active(p_org uuid,p_tax_code uuid,p_active boolean)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','finance_manager','accountant']::public.member_role[]) then raise exception 'Not authorized to manage tax codes'; end if;
  update public.tax_codes set is_active=p_active where org_id=p_org and id=p_tax_code;
  if not found then raise exception 'Tax code not found in this organization'; end if;
end;
$$;

create or replace function private.resolve_document_tax(
  p_org uuid,p_document_type text,p_issue_date date,p_tax_code uuid,p_amount numeric,p_require_active boolean
) returns table(tax_rate numeric,tax_amount numeric,tax_account_id uuid)
language plpgsql stable security definer set search_path = ''
as $$
declare tc public.tax_codes%rowtype;
begin
  if p_tax_code is null then return query select 0::numeric,0::numeric,null::uuid; return; end if;
  select * into tc from public.tax_codes where org_id=p_org and id=p_tax_code;
  if not found or (p_require_active and not tc.is_active) then raise exception 'Choose an active tax code in this organization'; end if;
  if p_issue_date<tc.effective_from or (tc.effective_to is not null and p_issue_date>tc.effective_to) then raise exception 'Tax code is not effective on the document date'; end if;
  if (p_document_type='invoice' and tc.scope not in ('sales','both')) or (p_document_type='bill' and tc.scope not in ('purchases','both')) then raise exception 'Tax code is not valid for this document type'; end if;
  if p_document_type='invoice' then
    if tc.rate>0 and not exists(select 1 from public.accounts a where a.org_id=p_org and a.id=tc.sales_account_id and a.is_active and a.type='liability') then raise exception 'Tax liability account is no longer active'; end if;
    return query select tc.rate,round(p_amount*tc.rate/100,4),tc.sales_account_id;
  else
    if tc.rate>0 and not exists(select 1 from public.accounts a where a.org_id=p_org and a.id=tc.purchase_account_id and a.is_active and a.type='asset') then raise exception 'Recoverable tax account is no longer active'; end if;
    return query select tc.rate,round(p_amount*tc.rate/100,4),tc.purchase_account_id;
  end if;
end;
$$;
revoke all on function private.resolve_document_tax(uuid,text,date,uuid,numeric,boolean) from public,anon,authenticated;

create or replace function private.document_journal_lines(p_document uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare d public.financial_documents%rowtype;gross_total numeric(30,4);lines jsonb;
begin
  select * into d from public.financial_documents where id=p_document;
  if not found then raise exception 'Financial document not found'; end if;
  if not exists(select 1 from public.organizations o where o.id=d.org_id and o.accounting_method='accrual') then raise exception 'Invoices and bills currently require accrual accounting'; end if;
  if not exists(select 1 from public.financial_parties p where p.org_id=d.org_id and p.id=d.party_id and p.is_active and p.party_type=case when d.document_type='invoice' then 'customer' else 'supplier' end) then raise exception 'Source customer or supplier is no longer active'; end if;
  if not exists(select 1 from public.accounts a where a.org_id=d.org_id and a.id=d.control_account_id and a.is_active and ((d.document_type='invoice' and a.type='asset' and a.reporting_class='receivable') or (d.document_type='bill' and a.type='liability' and a.reporting_class='payable'))) then raise exception 'Source receivable or payable account is no longer active'; end if;
  if exists(select 1 from public.financial_document_lines l join public.accounts a on a.org_id=l.org_id and a.id=l.account_id where l.org_id=d.org_id and l.document_id=d.id and (not a.is_active or a.type<>case when d.document_type='invoice' then 'revenue' else 'expense' end)) then raise exception 'Source line uses an inactive or unsupported account'; end if;
  if exists(select 1 from public.financial_document_lines l where l.org_id=d.org_id and l.document_id=d.id and l.tax_code_id is not null and (
      not exists(select 1 from public.tax_codes t where t.org_id=l.org_id and t.id=l.tax_code_id and d.issue_date>=t.effective_from and (t.effective_to is null or d.issue_date<=t.effective_to)
        and ((d.document_type='invoice' and t.scope in ('sales','both')) or (d.document_type='bill' and t.scope in ('purchases','both')))
        and t.rate=l.tax_rate and l.tax_amount=round(l.amount*t.rate/100,4)
        and l.tax_account_id=case when d.document_type='invoice' then t.sales_account_id else t.purchase_account_id end)
      or (l.tax_amount>0 and not exists(select 1 from public.accounts a where a.org_id=l.org_id and a.id=l.tax_account_id and a.is_active and a.type=case when d.document_type='invoice' then 'liability' else 'asset' end)))) then raise exception 'Document tax setup is no longer valid'; end if;
  select coalesce(sum(l.amount+l.tax_amount),0) into gross_total from public.financial_document_lines l where l.org_id=d.org_id and l.document_id=d.id;
  if gross_total<=0 then raise exception 'Add at least one positive document line'; end if;
  if d.document_type='invoice' then
    select jsonb_build_array(jsonb_build_object('account_id',d.control_account_id,'debit',gross_total::text,'credit','0','memo','Accounts receivable'))
      || coalesce(jsonb_agg(jsonb_build_object('account_id',l.account_id,'debit','0','credit',l.amount::text,'memo',l.description) order by l.id),'[]'::jsonb)
      || coalesce(jsonb_agg(jsonb_build_object('account_id',l.tax_account_id,'debit','0','credit',l.tax_amount::text,'memo','Tax · '||t.code) order by l.id) filter(where l.tax_amount>0),'[]'::jsonb)
      into lines from public.financial_document_lines l left join public.tax_codes t on t.org_id=l.org_id and t.id=l.tax_code_id where l.org_id=d.org_id and l.document_id=d.id;
  else
    select coalesce(jsonb_agg(jsonb_build_object('account_id',l.account_id,'debit',l.amount::text,'credit','0','memo',l.description) order by l.id),'[]'::jsonb)
      || coalesce(jsonb_agg(jsonb_build_object('account_id',l.tax_account_id,'debit',l.tax_amount::text,'credit','0','memo','Recoverable tax · '||t.code) order by l.id) filter(where l.tax_amount>0),'[]'::jsonb)
      || jsonb_build_array(jsonb_build_object('account_id',d.control_account_id,'debit','0','credit',gross_total::text,'memo','Accounts payable'))
      into lines from public.financial_document_lines l left join public.tax_codes t on t.org_id=l.org_id and t.id=l.tax_code_id where l.org_id=d.org_id and l.document_id=d.id;
  end if;
  return lines;
end;
$$;
revoke all on function private.document_journal_lines(uuid) from public,anon,authenticated;

create or replace function public.create_financial_document_draft(
  p_org uuid,p_document_type text,p_party uuid,p_document_number text,p_issue_date date,p_due_date date,p_control_account uuid,p_lines jsonb
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare actor uuid:=auth.uid();doc_id uuid;item jsonb;line_account uuid;line_amount numeric;line_description text;tax_id uuid;tax_rate numeric;tax_amount numeric;tax_account uuid;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to create receivables or payables'; end if;
  if p_document_type not in ('invoice','bill') then raise exception 'Choose invoice or bill'; end if;
  if not exists(select 1 from public.organizations o where o.id=p_org and o.accounting_method='accrual') then raise exception 'Invoices and bills currently require accrual accounting'; end if;
  if nullif(trim(p_document_number),'') is null or length(p_document_number)>80 then raise exception 'Document number is required'; end if;
  if p_issue_date is null or p_due_date is null or p_due_date<p_issue_date then raise exception 'Enter a valid document and due date'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<1 or jsonb_array_length(p_lines)>1000 then raise exception 'A document needs between 1 and 1000 lines'; end if;
  if not exists(select 1 from public.financial_parties p where p.org_id=p_org and p.id=p_party and p.is_active and p.party_type=case when p_document_type='invoice' then 'customer' else 'supplier' end) then raise exception 'Choose an active customer or supplier of the matching type'; end if;
  if not exists(select 1 from public.accounts a where a.org_id=p_org and a.id=p_control_account and a.is_active and ((p_document_type='invoice' and a.type='asset' and a.reporting_class='receivable') or (p_document_type='bill' and a.type='liability' and a.reporting_class='payable'))) then raise exception 'Choose an active receivable or payable control account'; end if;
  insert into public.financial_documents(org_id,document_type,document_number,party_id,control_account_id,issue_date,due_date,created_by) values(p_org,p_document_type,trim(p_document_number),p_party,p_control_account,p_issue_date,p_due_date,actor) returning id into doc_id;
  for item in select value from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(item)<>'object' then raise exception 'Document lines must be objects'; end if;
    line_account:=(item->>'account_id')::uuid;line_amount:=(item->>'amount')::numeric;line_description:=nullif(trim(item->>'description'),'');tax_id:=nullif(item->>'tax_code_id','')::uuid;
    if line_amount is null or line_amount<=0 or line_amount::text in ('NaN','Infinity','-Infinity') or line_amount<>round(line_amount,4) then raise exception 'Document lines need finite amounts greater than zero with at most four decimal places'; end if;
    if line_description is null or length(line_description)>500 then raise exception 'Enter a line description'; end if;
    if not exists(select 1 from public.accounts a where a.org_id=p_org and a.id=line_account and a.is_active and a.type=case when p_document_type='invoice' then 'revenue' else 'expense' end) then raise exception 'Invoice lines require active revenue accounts; bill lines require active expense accounts'; end if;
    select r.tax_rate,r.tax_amount,r.tax_account_id into tax_rate,tax_amount,tax_account from private.resolve_document_tax(p_org,p_document_type,p_issue_date,tax_id,line_amount,true) r;
    insert into public.financial_document_lines(org_id,document_id,account_id,description,amount,tax_code_id,tax_rate,tax_amount,tax_account_id)
      values(p_org,doc_id,line_account,line_description,line_amount,tax_id,tax_rate,tax_amount,tax_account);
  end loop;
  return doc_id;
end;
$$;

create or replace function public.update_financial_document_draft(p_document uuid,p_party uuid,p_document_number text,p_issue_date date,p_due_date date,p_control_account uuid,p_lines jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare d public.financial_documents%rowtype;actor uuid:=auth.uid();lines jsonb;item jsonb;line_account uuid;line_amount numeric;line_description text;tax_id uuid;tax_rate numeric;tax_amount numeric;tax_account uuid;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  select * into d from public.financial_documents where id=p_document for update;
  if not found then raise exception 'Financial document not found'; end if;
  if d.created_by<>actor then raise exception 'Only the draft creator may edit this document'; end if;
  if not private.has_role(d.org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to edit this document'; end if;
  if d.status<>'draft' then raise exception 'Only draft documents can be edited'; end if;
  if p_due_date is null or p_issue_date is null or p_due_date<p_issue_date then raise exception 'Enter a valid document and due date'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<1 or jsonb_array_length(p_lines)>1000 then raise exception 'A document needs between 1 and 1000 lines'; end if;
  if not exists(select 1 from public.financial_parties p where p.org_id=d.org_id and p.id=p_party and p.is_active and p.party_type=case when d.document_type='invoice' then 'customer' else 'supplier' end) then raise exception 'Choose an active party of the matching type'; end if;
  if nullif(trim(p_document_number),'') is null or length(p_document_number)>80 then raise exception 'Document number is required'; end if;
  if not exists(select 1 from public.accounts a where a.org_id=d.org_id and a.id=p_control_account and a.is_active and ((d.document_type='invoice' and a.type='asset' and a.reporting_class='receivable') or (d.document_type='bill' and a.type='liability' and a.reporting_class='payable'))) then raise exception 'Choose an active control account'; end if;
  delete from public.financial_document_lines where org_id=d.org_id and document_id=d.id;
  for item in select value from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(item)<>'object' then raise exception 'Document lines must be objects'; end if;
    line_account:=(item->>'account_id')::uuid;line_amount:=(item->>'amount')::numeric;line_description:=nullif(trim(item->>'description'),'');tax_id:=nullif(item->>'tax_code_id','')::uuid;
    if line_amount is null or line_amount<=0 or line_amount::text in ('NaN','Infinity','-Infinity') or line_amount<>round(line_amount,4) then raise exception 'Document line amount is invalid'; end if;
    if line_description is null or length(line_description)>500 then raise exception 'Enter a line description'; end if;
    if not exists(select 1 from public.accounts a where a.org_id=d.org_id and a.id=line_account and a.is_active and a.type=case when d.document_type='invoice' then 'revenue' else 'expense' end) then raise exception 'Document line account has the wrong account type'; end if;
    select r.tax_rate,r.tax_amount,r.tax_account_id into tax_rate,tax_amount,tax_account from private.resolve_document_tax(d.org_id,d.document_type,p_issue_date,tax_id,line_amount,false) r;
    insert into public.financial_document_lines(org_id,document_id,account_id,description,amount,tax_code_id,tax_rate,tax_amount,tax_account_id) values(d.org_id,d.id,line_account,line_description,line_amount,tax_id,tax_rate,tax_amount,tax_account);
  end loop;
  update public.financial_documents set party_id=p_party,document_number=trim(p_document_number),issue_date=p_issue_date,due_date=p_due_date,control_account_id=p_control_account,updated_at=now() where id=d.id;
  if d.journal_entry_id is not null then
    lines:=private.document_journal_lines(d.id);
    perform public.update_journal_entry_draft(d.journal_entry_id,p_issue_date,trim(p_document_number),'Document '||trim(p_document_number),lines);
  end if;
end;
$$;

create or replace function public.record_financial_document_payment(p_document uuid,p_payment_date date,p_account uuid,p_amount numeric,p_reference text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare d public.financial_documents%rowtype;actor uuid:=auth.uid();reserved numeric(30,4);gross_total numeric(30,4);org_currency char(3);new_payment uuid;journal_id uuid;payment_lines jsonb;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  select * into d from public.financial_documents where id=p_document for update;
  if not found then raise exception 'Financial document not found'; end if;
  if not private.has_role(d.org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to record payments'; end if;
  if d.status<>'issued' then raise exception 'Payments require an issued invoice or bill'; end if;
  if p_payment_date is null then raise exception 'Payment date is required'; end if;
  perform private.assert_open_period(d.org_id,p_payment_date);
  if p_amount is null or p_amount<=0 or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<>round(p_amount,4) then raise exception 'Payment amount must be finite, positive, and have at most four decimal places'; end if;
  if length(coalesce(p_reference,''))>120 then raise exception 'Payment reference is too long'; end if;
  if not exists(select 1 from public.accounts a where a.org_id=d.org_id and a.id=p_account and a.is_active and a.type='asset' and a.reporting_class in ('cash','bank')) then raise exception 'Choose an active cash or bank account'; end if;
  select coalesce(sum(l.amount+l.tax_amount),0) into gross_total from public.financial_document_lines l where l.org_id=d.org_id and l.document_id=d.id;
  select coalesce(sum(p.amount),0) into reserved from public.financial_document_payments p join public.journal_entries e on e.org_id=p.org_id and e.id=p.journal_entry_id where p.org_id=d.org_id and p.document_id=d.id and e.status in ('submitted','pending_approval','approved','posted');
  if p_amount+reserved>gross_total then raise exception 'Payment exceeds the unpaid document balance'; end if;
  insert into public.financial_document_payments(org_id,document_id,payment_date,account_id,amount,reference,created_by) values(d.org_id,d.id,p_payment_date,p_account,p_amount,nullif(trim(p_reference),''),actor) returning id into new_payment;
  if d.document_type='invoice' then
    payment_lines:=jsonb_build_array(jsonb_build_object('account_id',p_account,'debit',p_amount::text,'credit','0','memo','Customer receipt'),jsonb_build_object('account_id',d.control_account_id,'debit','0','credit',p_amount::text,'memo','Reduce accounts receivable'));
  else
    payment_lines:=jsonb_build_array(jsonb_build_object('account_id',d.control_account_id,'debit',p_amount::text,'credit','0','memo','Reduce accounts payable'),jsonb_build_object('account_id',p_account,'debit','0','credit',p_amount::text,'memo','Supplier payment'));
  end if;
  select base_currency into org_currency from public.organizations where id=d.org_id;
  journal_id:=public.create_journal_entry_draft(d.org_id,p_payment_date,nullif(trim(p_reference),''),'Payment for '||d.document_number,org_currency,1,case when d.document_type='invoice' then 'customer_payment' else 'supplier_payment' end,payment_lines);
  update public.financial_document_payments set journal_entry_id=journal_id where id=new_payment;
  perform public.submit_journal_entry(journal_id);
  return journal_id;
end;
$$;

create or replace function public.resubmit_financial_document_payment(p_payment uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare payment public.financial_document_payments%rowtype;d public.financial_documents%rowtype;actor uuid:=auth.uid();document_id uuid;reserved numeric(30,4);gross_total numeric(30,4);lines jsonb;journal_state public.entry_status;
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
  if not exists(select 1 from public.accounts a where a.org_id=d.org_id and a.id=payment.account_id and a.is_active and a.type='asset' and a.reporting_class in ('cash','bank')) then raise exception 'The payment cash or bank account is no longer active'; end if;
  select coalesce(sum(l.amount+l.tax_amount),0) into gross_total from public.financial_document_lines l where l.org_id=d.org_id and l.document_id=d.id;
  select coalesce(sum(p.amount),0) into reserved from public.financial_document_payments p join public.journal_entries e on e.org_id=p.org_id and e.id=p.journal_entry_id where p.org_id=d.org_id and p.document_id=d.id and p.id<>payment.id and e.status in ('submitted','pending_approval','approved','posted');
  if payment.amount+reserved>gross_total then raise exception 'Payment now exceeds the unpaid document balance'; end if;
  if d.document_type='invoice' then
    lines:=jsonb_build_array(jsonb_build_object('account_id',payment.account_id,'debit',payment.amount::text,'credit','0','memo','Customer receipt'),jsonb_build_object('account_id',d.control_account_id,'debit','0','credit',payment.amount::text,'memo','Reduce accounts receivable'));
  else
    lines:=jsonb_build_array(jsonb_build_object('account_id',d.control_account_id,'debit',payment.amount::text,'credit','0','memo','Reduce accounts payable'),jsonb_build_object('account_id',payment.account_id,'debit','0','credit',payment.amount::text,'memo','Supplier payment'));
  end if;
  perform public.update_journal_entry_draft(payment.journal_entry_id,payment.payment_date,payment.reference,'Payment for '||d.document_number,lines);
  perform public.submit_journal_entry(payment.journal_entry_id);
  return payment.journal_entry_id;
end;
$$;

create or replace view public.financial_documents_exact with (security_invoker=true) as
select d.id,d.org_id,d.document_type,d.document_number,d.party_id,p.name party_name,d.control_account_id,d.issue_date,d.due_date,
  d.status journal_status,d.journal_entry_id,d.created_by,d.created_at,
  coalesce((select sum(l.amount+l.tax_amount) from public.financial_document_lines l where l.org_id=d.org_id and l.document_id=d.id),0)::text total,
  coalesce((select sum(pay.amount) from public.financial_document_payments pay join public.journal_entries e on e.org_id=pay.org_id and e.id=pay.journal_entry_id and e.status='posted' where pay.org_id=d.org_id and pay.document_id=d.id),0)::text paid,
  (coalesce((select sum(l.amount+l.tax_amount) from public.financial_document_lines l where l.org_id=d.org_id and l.document_id=d.id),0)-coalesce((select sum(pay.amount) from public.financial_document_payments pay join public.journal_entries e on e.org_id=pay.org_id and e.id=pay.journal_entry_id and e.status='posted' where pay.org_id=d.org_id and pay.document_id=d.id),0))::text outstanding,
  case when d.status<>'issued' then d.status when coalesce((select sum(pay.amount) from public.financial_document_payments pay join public.journal_entries e on e.org_id=pay.org_id and e.id=pay.journal_entry_id and e.status='posted' where pay.org_id=d.org_id and pay.document_id=d.id),0)=0 then 'issued'
    when coalesce((select sum(pay.amount) from public.financial_document_payments pay join public.journal_entries e on e.org_id=pay.org_id and e.id=pay.journal_entry_id and e.status='posted' where pay.org_id=d.org_id and pay.document_id=d.id),0)>=coalesce((select sum(l.amount+l.tax_amount) from public.financial_document_lines l where l.org_id=d.org_id and l.document_id=d.id),0) then 'paid' else 'partially_paid' end collection_status
from public.financial_documents d join public.financial_parties p on p.org_id=d.org_id and p.id=d.party_id;
revoke all on public.financial_documents_exact from public,anon,authenticated;
grant select on public.financial_documents_exact to authenticated;

create or replace function public.tax_activity_exact(p_org uuid,p_from date,p_to date)
returns table(tax_code_id uuid,code text,name text,rate text,sales_tax text,purchase_tax text,net_tax text)
language plpgsql stable security invoker set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_from is null or p_to is null or p_from>p_to then raise exception 'Choose a valid tax reporting period'; end if;
  if not private.has_role(p_org,array['owner','administrator','finance_manager','accountant','approver','auditor','viewer']::public.member_role[]) then raise exception 'Not authorized to view this organization'; end if;
  return query
  with recursive source_lines as (
    select d.id document_id,d.org_id,d.document_type,l.tax_code_id,l.tax_amount,e.id entry_id,e.entry_date,0 depth,e.status
    from public.financial_documents d join public.journal_entries e on e.org_id=d.org_id and e.id=d.journal_entry_id
    join public.financial_document_lines l on l.org_id=d.org_id and l.document_id=d.id
    where d.org_id=p_org and e.status in ('posted','reversed') and l.tax_code_id is not null
  ), journal_chain as (
    select * from source_lines
    union all
    select c.document_id,c.org_id,c.document_type,c.tax_code_id,c.tax_amount,child.id,child.entry_date,c.depth+1,child.status
    from journal_chain c join public.journal_entries child on child.org_id=c.org_id and child.reverses_id=c.entry_id
    where child.status in ('posted','reversed')
  ), movements as (
    select tax_code_id,document_type,case when mod(depth,2)=0 then tax_amount else -tax_amount end amount
    from journal_chain where status in ('posted','reversed') and entry_date between p_from and p_to
  ), totals as (
    select m.tax_code_id,coalesce(sum(m.amount) filter(where m.document_type='invoice'),0) sales,
      coalesce(sum(m.amount) filter(where m.document_type='bill'),0) purchases
    from movements m group by m.tax_code_id
  )
  select t.id,t.code,t.name,t.rate::text,x.sales::text,x.purchases::text,(x.sales-x.purchases)::text
  from totals x join public.tax_codes t on t.org_id=p_org and t.id=x.tax_code_id order by t.code;
end;
$$;

revoke all on function public.create_tax_code(uuid,text,text,text,numeric,uuid,uuid,date,date) from public,anon,authenticated;
revoke all on function public.set_tax_code_active(uuid,uuid,boolean) from public,anon,authenticated;
revoke all on function public.tax_activity_exact(uuid,date,date) from public,anon,authenticated;
revoke all on function public.create_financial_document_draft(uuid,text,uuid,text,date,date,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.update_financial_document_draft(uuid,uuid,text,date,date,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.record_financial_document_payment(uuid,date,uuid,numeric,text) from public,anon,authenticated;
revoke all on function public.resubmit_financial_document_payment(uuid) from public,anon,authenticated;
grant execute on function public.create_tax_code(uuid,text,text,text,numeric,uuid,uuid,date,date) to authenticated;
grant execute on function public.set_tax_code_active(uuid,uuid,boolean) to authenticated;
grant execute on function public.tax_activity_exact(uuid,date,date) to authenticated;
grant execute on function public.create_financial_document_draft(uuid,text,uuid,text,date,date,uuid,jsonb) to authenticated;
grant execute on function public.update_financial_document_draft(uuid,uuid,text,date,date,uuid,jsonb) to authenticated;
grant execute on function public.record_financial_document_payment(uuid,date,uuid,numeric,text) to authenticated;
grant execute on function public.resubmit_financial_document_payment(uuid) to authenticated;
