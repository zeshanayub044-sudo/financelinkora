-- Private, bounded receipt storage. Existing bucket names are never reused or
-- reconfigured by this migration; a collision stops the transaction.
create table public.receipt_attachments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  entry_id uuid not null,
  storage_path text not null unique,
  original_name text not null check(length(original_name) between 1 and 255),
  mime_type text not null check(mime_type in ('application/pdf','image/jpeg','image/png')),
  size_bytes bigint not null check(size_bytes between 1 and 10485760),
  uploaded_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique(org_id,id),
  foreign key(org_id,entry_id) references public.journal_entries(org_id,id) on delete restrict
);
create index receipt_attachments_entry_idx on public.receipt_attachments(org_id,entry_id,created_at desc);
alter table public.receipt_attachments enable row level security;
create policy receipt_attachments_read on public.receipt_attachments for select to authenticated
  using(private.has_role(org_id,array['owner','administrator','finance_manager','accountant','auditor','viewer']::public.member_role[]));
grant select on public.receipt_attachments to authenticated;
revoke all on public.receipt_attachments from anon;
revoke insert,update,delete on public.receipt_attachments from authenticated;
create trigger audit_receipt_attachments after insert or update or delete on public.receipt_attachments for each row execute function private.audit_row();

do $$
begin
  if exists(select 1 from storage.buckets where id='linkora-finance-receipts') then
    raise exception 'Storage bucket linkora-finance-receipts already exists; inspect it before applying the receipt migration';
  end if;
  insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
    values('linkora-finance-receipts','linkora-finance-receipts',false,10485760,array['application/pdf','image/jpeg','image/png']);
end;
$$;

create policy linkora_receipts_upload on storage.objects for insert to authenticated
  with check(
    bucket_id='linkora-finance-receipts'
    and cardinality(storage.foldername(name))=2
    and exists(
      select 1 from public.journal_entries e
      where e.org_id::text=(storage.foldername(name))[1]
        and e.id::text=(storage.foldername(name))[2]
        and e.entry_kind in ('income','expense')
        and private.has_role(e.org_id,array['owner','administrator','finance_manager','accountant']::public.member_role[])
    )
  );
create policy linkora_receipts_read on storage.objects for select to authenticated
  using(
    bucket_id='linkora-finance-receipts'
    and exists(select 1 from public.receipt_attachments r where r.storage_path=name
      and private.has_role(r.org_id,array['owner','administrator','finance_manager','accountant','auditor','viewer']::public.member_role[]))
  );
create policy linkora_receipts_orphan_cleanup on storage.objects for delete to authenticated
  using(
    bucket_id='linkora-finance-receipts'
    and not exists(select 1 from public.receipt_attachments r where r.storage_path=name)
    and cardinality(storage.foldername(name))=2
    and exists(
      select 1 from public.journal_entries e
      where e.org_id::text=(storage.foldername(name))[1]
        and e.id::text=(storage.foldername(name))[2]
        and e.entry_kind in ('income','expense')
        and private.has_role(e.org_id,array['owner','administrator','finance_manager','accountant']::public.member_role[])
    )
  );
-- Restrictive guards make these bucket rules hold even if another application
-- has a broader permissive Storage policy on storage.objects.
create policy linkora_receipts_upload_guard on storage.objects as restrictive for insert to authenticated
  with check(
    bucket_id<>'linkora-finance-receipts'
    or (cardinality(storage.foldername(name))=2 and exists(
      select 1 from public.journal_entries e
      where e.org_id::text=(storage.foldername(name))[1] and e.id::text=(storage.foldername(name))[2]
        and e.entry_kind in ('income','expense')
        and private.has_role(e.org_id,array['owner','administrator','finance_manager','accountant']::public.member_role[])
    ))
  );
create policy linkora_receipts_read_guard on storage.objects as restrictive for select to authenticated
  using(bucket_id<>'linkora-finance-receipts' or exists(
    select 1 from public.receipt_attachments r where r.storage_path=name
      and private.has_role(r.org_id,array['owner','administrator','finance_manager','accountant','auditor','viewer']::public.member_role[])
  ));
create policy linkora_receipts_delete_guard on storage.objects as restrictive for delete to authenticated
  using(bucket_id<>'linkora-finance-receipts' or (
    not exists(select 1 from public.receipt_attachments r where r.storage_path=name)
    and cardinality(storage.foldername(name))=2
    and exists(select 1 from public.journal_entries e
      where e.org_id::text=(storage.foldername(name))[1] and e.id::text=(storage.foldername(name))[2]
        and e.entry_kind in ('income','expense')
        and private.has_role(e.org_id,array['owner','administrator','finance_manager','accountant']::public.member_role[]))
  ));
create policy linkora_receipts_update_guard on storage.objects as restrictive for update to authenticated
  using(bucket_id<>'linkora-finance-receipts') with check(bucket_id<>'linkora-finance-receipts');
create policy linkora_receipts_anonymous_deny on storage.objects as restrictive for all to anon
  using(bucket_id<>'linkora-finance-receipts') with check(bucket_id<>'linkora-finance-receipts');
create or replace function public.register_receipt_attachment(
  p_org uuid,p_entry uuid,p_storage_path text,p_original_name text,p_mime_type text,p_size_bytes bigint
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare actor uuid:=auth.uid();new_id uuid;
begin
  if actor is null then raise exception 'Not authenticated'; end if;
  if not private.has_role(p_org,array['owner','administrator','finance_manager','accountant']::public.member_role[]) then raise exception 'Not authorized to upload receipts'; end if;
  if p_original_name is null or length(trim(p_original_name)) not between 1 and 255 or p_original_name~'[/\\]' then raise exception 'Enter a valid receipt filename'; end if;
  if p_mime_type not in ('application/pdf','image/jpeg','image/png') then raise exception 'Receipts must be PDF, JPEG, or PNG files'; end if;
  if p_size_bytes is null or p_size_bytes not between 1 and 10485760 then raise exception 'Receipt files must be 10 MB or smaller'; end if;
  if p_storage_path is null or cardinality(storage.foldername(p_storage_path))<>2
    or (storage.foldername(p_storage_path))[1]<>p_org::text or (storage.foldername(p_storage_path))[2]<>p_entry::text then
    raise exception 'Receipt storage path does not match this organization and entry';
  end if;
  if not exists(select 1 from public.journal_entries e where e.org_id=p_org and e.id=p_entry and e.entry_kind in ('income','expense')) then raise exception 'Receipts can only be attached to income or expense entries'; end if;
  if not exists(select 1 from storage.objects o where o.bucket_id='linkora-finance-receipts' and o.name=p_storage_path) then raise exception 'Uploaded receipt object was not found'; end if;
  insert into public.receipt_attachments(org_id,entry_id,storage_path,original_name,mime_type,size_bytes,uploaded_by)
    values(p_org,p_entry,p_storage_path,trim(p_original_name),p_mime_type,p_size_bytes,actor) returning id into new_id;
  return new_id;
end;
$$;
revoke all on function public.register_receipt_attachment(uuid,uuid,text,text,text,bigint) from public,anon,authenticated;
grant execute on function public.register_receipt_attachment(uuid,uuid,text,text,text,bigint) to authenticated;
