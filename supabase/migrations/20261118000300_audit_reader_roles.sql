-- Finance managers and approvers need read access to the organization audit
-- trail for actions they can perform. The policy remains organization-scoped.
drop policy if exists audit_read on public.audit_logs;
create policy audit_read on public.audit_logs for select to authenticated
  using (private.has_role(org_id,array[
    'owner','administrator','finance_manager','approver','auditor','viewer'
  ]::public.member_role[]));
