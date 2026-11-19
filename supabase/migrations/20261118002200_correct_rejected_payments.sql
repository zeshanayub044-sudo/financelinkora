-- Update a rejected reservation and resubmit its existing linked journal in a
-- single transaction. This preserves payment identity and its audit history.
create or replace function public.correct_and_resubmit_financial_document_payment(
  p_payment uuid,p_payment_date date,p_account uuid,p_amount numeric,p_reference text
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare payment public.financial_document_payments%rowtype;d public.financial_documents%rowtype;actor uuid:=auth.uid();entry_state public.entry_status;rejection text;total_reserved numeric(30,4);document_total numeric(30,4);lines jsonb;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  select doc.* into d from public.financial_documents doc join public.financial_document_payments pay on pay.org_id=doc.org_id and pay.document_id=doc.id where pay.id=p_payment for update of doc;
  if not found then raise exception 'Payment not found'; end if;
  select * into payment from public.financial_document_payments where org_id=d.org_id and id=p_payment for update;
  if payment.created_by<>actor then raise exception 'Only the payment creator may correct it'; end if;
  if not private.has_role(d.org_id,array['owner','administrator','accountant','finance_manager']::public.member_role[]) then raise exception 'Not authorized to correct this payment'; end if;
  if d.status<>'issued' or payment.journal_entry_id is null then raise exception 'Payment is not eligible for correction'; end if;
  select status,rejection_reason into entry_state,rejection from public.journal_entries where org_id=d.org_id and id=payment.journal_entry_id for update;
  if not found or entry_state<>'draft' or nullif(trim(rejection),'') is null then raise exception 'Only a rejected payment draft can be corrected'; end if;
  if p_payment_date is null then raise exception 'Payment date is required'; end if;
  perform private.assert_open_period(d.org_id,p_payment_date);
  if p_amount is null or p_amount<=0 or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<>round(p_amount,4) then raise exception 'Payment amount must be finite, positive, and have at most four decimal places'; end if;
  if length(coalesce(p_reference,''))>120 then raise exception 'Payment reference is too long'; end if;
  if not exists(select 1 from public.accounts a where a.org_id=d.org_id and a.id=p_account and a.is_active and a.type='asset' and a.reporting_class in ('cash','bank')) then raise exception 'Choose an active cash or bank account'; end if;
  select coalesce(sum(l.amount),0) into document_total from public.financial_document_lines l where l.org_id=d.org_id and l.document_id=d.id;
  select coalesce(sum(other.amount),0) into total_reserved
    from public.financial_document_payments other join public.journal_entries e on e.org_id=other.org_id and e.id=other.journal_entry_id
    where other.org_id=d.org_id and other.document_id=d.id and other.id<>payment.id and e.status in ('submitted','pending_approval','approved','posted');
  if p_amount+total_reserved>document_total then raise exception 'Payment exceeds the unpaid document balance'; end if;
  update public.financial_document_payments set payment_date=p_payment_date,account_id=p_account,amount=p_amount,reference=nullif(trim(p_reference),'') where id=payment.id;
  if d.document_type='invoice' then
    lines:=jsonb_build_array(jsonb_build_object('account_id',p_account,'debit',p_amount::text,'credit','0','memo','Customer receipt'),jsonb_build_object('account_id',d.control_account_id,'debit','0','credit',p_amount::text,'memo','Reduce accounts receivable'));
  else
    lines:=jsonb_build_array(jsonb_build_object('account_id',d.control_account_id,'debit',p_amount::text,'credit','0','memo','Reduce accounts payable'),jsonb_build_object('account_id',p_account,'debit','0','credit',p_amount::text,'memo','Supplier payment'));
  end if;
  perform public.update_journal_entry_draft(payment.journal_entry_id,p_payment_date,nullif(trim(p_reference),''),'Payment for '||d.document_number,lines);
  perform public.submit_journal_entry(payment.journal_entry_id);
  update public.journal_entries set rejection_reason=null,rejected_at=null,rejected_by=null where id=payment.journal_entry_id;
  return payment.journal_entry_id;
end;
$$;
revoke all on function public.correct_and_resubmit_financial_document_payment(uuid,date,uuid,numeric,text) from public,anon,authenticated;
grant execute on function public.correct_and_resubmit_financial_document_payment(uuid,date,uuid,numeric,text) to authenticated;
