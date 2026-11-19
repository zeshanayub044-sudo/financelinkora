-- Add workflow states and scoped roles without rewriting historical migrations.
alter type public.member_role add value if not exists 'approver';
alter type public.member_role add value if not exists 'viewer';
alter type public.entry_status add value if not exists 'submitted' after 'draft';
alter type public.entry_status add value if not exists 'pending_approval' after 'submitted';
alter type public.entry_status add value if not exists 'rejected' after 'pending_approval';
