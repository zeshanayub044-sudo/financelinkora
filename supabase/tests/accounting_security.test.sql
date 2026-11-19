-- Local-only synthetic accounting/security tests. This entire file runs inside a
-- transaction and rolls back; never run it against a linked/hosted project.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public,extensions;
select plan(200);

select ok(to_regclass('public.fixed_asset_disposals') is not null,'fixed-asset disposal records are installed');
select ok((select relrowsecurity from pg_class where oid='public.fixed_asset_disposals'::regclass),'fixed-asset disposals enforce row level security');
select ok(not has_table_privilege('authenticated','public.fixed_asset_disposals','insert'),'clients cannot create disposal records directly');
select ok(has_function_privilege('authenticated','public.create_fixed_asset_disposal_draft(uuid,uuid,date,numeric,uuid,uuid,uuid)','execute'),'authenticated disposal creation uses the validated journal RPC');
select ok(exists(select 1 from pg_trigger where tgrelid='public.journal_entries'::regclass and tgname='guard_fixed_asset_disposal_entry' and not tgisinternal),'journal status changes enforce disposal line integrity');
select ok(to_regclass('public.fiscal_year_closings') is not null,'fiscal-year close records are installed');
select ok((select relrowsecurity from pg_class where oid='public.fiscal_year_closings'::regclass),'fiscal-year close records enforce row level security');
select ok(not has_table_privilege('authenticated','public.fiscal_year_closings','insert'),'clients cannot create fiscal close records directly');
select ok(has_function_privilege('authenticated','public.create_fiscal_year_close_draft(uuid,uuid,uuid)','execute'),'fiscal close creation is exposed only through its validated workflow');
select ok(exists(select 1 from pg_trigger where tgrelid='public.accounting_periods'::regclass and tgname='guard_fiscal_year_period_lock' and not tgisinternal),'fiscal year period lock requires an approved closing journal');

select set_config('linkora_test.org_a',gen_random_uuid()::text,true);
select set_config('linkora_test.org_b',gen_random_uuid()::text,true);
select set_config('linkora_test.org_c',gen_random_uuid()::text,true);
select set_config('linkora_test.maker',gen_random_uuid()::text,true);
select set_config('linkora_test.checker',gen_random_uuid()::text,true);
select set_config('linkora_test.outsider',gen_random_uuid()::text,true);
select set_config('linkora_test.cash',gen_random_uuid()::text,true);
select set_config('linkora_test.revenue',gen_random_uuid()::text,true);
select set_config('linkora_test.tax_liability',gen_random_uuid()::text,true);
select set_config('linkora_test.tax_code',gen_random_uuid()::text,true);
select set_config('linkora_test.purchase_tax_code',gen_random_uuid()::text,true);
select set_config('linkora_test.supplier',gen_random_uuid()::text,true);
select set_config('linkora_test.bill',gen_random_uuid()::text,true);
select set_config('linkora_test.expense',gen_random_uuid()::text,true);
select set_config('linkora_test.payroll_expense',gen_random_uuid()::text,true);
select set_config('linkora_test.payroll_liability',gen_random_uuid()::text,true);
select set_config('linkora_test.payroll_employee',gen_random_uuid()::text,true);
select set_config('linkora_test.payroll_component',gen_random_uuid()::text,true);
select set_config('linkora_test.payroll_run',gen_random_uuid()::text,true);
select set_config('linkora_test.payroll_journal',gen_random_uuid()::text,true);
select set_config('linkora_test.recurring_template',gen_random_uuid()::text,true);
select set_config('linkora_test.recurring_entry',gen_random_uuid()::text,true);
select set_config('linkora_test.rejected_payment',gen_random_uuid()::text,true);
select set_config('linkora_test.rejected_payment_entry',gen_random_uuid()::text,true);
select set_config('linkora_test.fixed_asset_account',gen_random_uuid()::text,true);
select set_config('linkora_test.close_cash',gen_random_uuid()::text,true);
select set_config('linkora_test.close_revenue',gen_random_uuid()::text,true);
select set_config('linkora_test.close_expense',gen_random_uuid()::text,true);
select set_config('linkora_test.close_equity',gen_random_uuid()::text,true);
select set_config('linkora_test.close_source',gen_random_uuid()::text,true);
select set_config('linkora_test.close_entry',gen_random_uuid()::text,true);
select set_config('linkora_test.close_reversal',gen_random_uuid()::text,true);
select set_config('linkora_test.close_retry',gen_random_uuid()::text,true);
select set_config('linkora_test.starter_contra',gen_random_uuid()::text,true);
select set_config('linkora_test.accum_depreciation_account',gen_random_uuid()::text,true);
select set_config('linkora_test.depreciation_expense_account',gen_random_uuid()::text,true);
select set_config('linkora_test.department',gen_random_uuid()::text,true);
select set_config('linkora_test.project',gen_random_uuid()::text,true);
select set_config('linkora_test.bank',gen_random_uuid()::text,true);
select set_config('linkora_test.receivable',gen_random_uuid()::text,true);
select set_config('linkora_test.payable',gen_random_uuid()::text,true);
select set_config('linkora_test.unclassified',gen_random_uuid()::text,true);
select set_config('linkora_test.budget',gen_random_uuid()::text,true);
select set_config('linkora_test.statement_import',gen_random_uuid()::text,true);
select set_config('linkora_test.statement_row',gen_random_uuid()::text,true);
select set_config('linkora_test.bank_line',gen_random_uuid()::text,true);
select set_config('linkora_test.org_b_cash',gen_random_uuid()::text,true);
select set_config('linkora_test.org_b_bank',gen_random_uuid()::text,true);
select set_config('linkora_test.org_b_entry',gen_random_uuid()::text,true);
select set_config('linkora_test.org_b_bank_line',gen_random_uuid()::text,true);
select set_config('linkora_test.org_b_import',gen_random_uuid()::text,true);
select set_config('linkora_test.org_b_row',gen_random_uuid()::text,true);
select set_config('linkora_test.month_start',date_trunc('month',current_date)::date::text,true);
select set_config('linkora_test.month_end',(date_trunc('month',current_date)+interval '1 month'-interval '1 day')::date::text,true);

insert into auth.users(id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data)
values
 (current_setting('linkora_test.maker')::uuid,'authenticated','authenticated','maker-'||gen_random_uuid()||'@linkora.test','','{}','{}'),
 (current_setting('linkora_test.checker')::uuid,'authenticated','authenticated','checker-'||gen_random_uuid()||'@linkora.test','','{}','{}'),
 (current_setting('linkora_test.outsider')::uuid,'authenticated','authenticated','outsider-'||gen_random_uuid()||'@linkora.test','','{}','{}');

insert into public.organizations(id,name,base_currency,fy_start_month)
values
 (current_setting('linkora_test.org_a')::uuid,'Local test org A','USD',extract(month from current_date)::integer),
 (current_setting('linkora_test.org_b')::uuid,'Local test org B','USD',extract(month from current_date)::integer),
 (current_setting('linkora_test.org_c')::uuid,'Local fiscal close test org','USD',1);
insert into public.organization_members(org_id,user_id,role) values
 (current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.maker')::uuid,'owner'),
 (current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.checker')::uuid,'finance_manager'),
 (current_setting('linkora_test.org_b')::uuid,current_setting('linkora_test.outsider')::uuid,'owner'),
 (current_setting('linkora_test.org_b')::uuid,current_setting('linkora_test.maker')::uuid,'finance_manager'),
 (current_setting('linkora_test.org_c')::uuid,current_setting('linkora_test.maker')::uuid,'owner'),
 (current_setting('linkora_test.org_c')::uuid,current_setting('linkora_test.checker')::uuid,'finance_manager');
insert into public.accounts(id,org_id,code,name,type,reporting_class) values
 (current_setting('linkora_test.cash')::uuid,current_setting('linkora_test.org_a')::uuid,'1000','Test cash','asset','cash'),
 (current_setting('linkora_test.bank')::uuid,current_setting('linkora_test.org_a')::uuid,'1010','Test bank','asset','bank'),
 (current_setting('linkora_test.receivable')::uuid,current_setting('linkora_test.org_a')::uuid,'1200','Test receivable','asset','receivable'),
 (current_setting('linkora_test.payable')::uuid,current_setting('linkora_test.org_a')::uuid,'2100','Test payable','liability','payable'),
 (current_setting('linkora_test.unclassified')::uuid,current_setting('linkora_test.org_a')::uuid,'1990','Unclassified asset','asset',null),
 (current_setting('linkora_test.fixed_asset_account')::uuid,current_setting('linkora_test.org_a')::uuid,'1600','Test equipment','asset',null),
 (current_setting('linkora_test.starter_contra')::uuid,current_setting('linkora_test.org_a')::uuid,'1590','Starter accumulated depreciation','asset',null),
 (current_setting('linkora_test.accum_depreciation_account')::uuid,current_setting('linkora_test.org_a')::uuid,'1690','Accumulated depreciation - equipment','asset','accumulated_depreciation'),
 (current_setting('linkora_test.revenue')::uuid,current_setting('linkora_test.org_a')::uuid,'4000','Test revenue','revenue',null),
 (current_setting('linkora_test.tax_liability')::uuid,current_setting('linkora_test.org_a')::uuid,'2300','Test output tax payable','liability',null),
 (current_setting('linkora_test.expense')::uuid,current_setting('linkora_test.org_a')::uuid,'5000','Test expense','expense',null),
 (current_setting('linkora_test.payroll_expense')::uuid,current_setting('linkora_test.org_a')::uuid,'5100','Payroll expense','expense',null),
 (current_setting('linkora_test.payroll_liability')::uuid,current_setting('linkora_test.org_a')::uuid,'2310','Payroll payable','liability',null),
 (current_setting('linkora_test.depreciation_expense_account')::uuid,current_setting('linkora_test.org_a')::uuid,'6100','Depreciation expense','expense',null),
 (current_setting('linkora_test.org_b_cash')::uuid,current_setting('linkora_test.org_b')::uuid,'1000','Test B cash','asset','cash'),
 (current_setting('linkora_test.org_b_bank')::uuid,current_setting('linkora_test.org_b')::uuid,'1010','Test B bank','asset','bank'),
 (current_setting('linkora_test.close_cash')::uuid,current_setting('linkora_test.org_c')::uuid,'1000','Close test cash','asset','cash'),
 (current_setting('linkora_test.close_revenue')::uuid,current_setting('linkora_test.org_c')::uuid,'4000','Close test revenue','revenue',null),
 (current_setting('linkora_test.close_expense')::uuid,current_setting('linkora_test.org_c')::uuid,'5000','Close test expense','expense',null),
 (current_setting('linkora_test.close_equity')::uuid,current_setting('linkora_test.org_c')::uuid,'3100','Close test retained earnings','equity',null);

select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
set local role authenticated;

select ok((select relrowsecurity from pg_class where oid='public.receipt_attachments'::regclass),'receipt metadata enforces row level security');
select is((select public from storage.buckets where id='linkora-finance-receipts'),false,'receipt bucket is private');
select ok(not has_table_privilege('authenticated','public.audit_logs','insert'),'authenticated users cannot insert audit rows directly');
select ok(not has_table_privilege('authenticated','public.audit_logs','update'),'authenticated users cannot update audit rows directly');
select ok(not has_table_privilege('authenticated','public.audit_logs','delete'),'authenticated users cannot delete audit rows directly');
select is((select count(*)::integer from public.audit_logs where org_id=current_setting('linkora_test.org_b')::uuid),0,'audit log RLS hides another organization');
select ok(not has_function_privilege('anon','public.create_organization(text,text,text,text,char,integer,text,text)','execute'),'anonymous users cannot create organizations');
select set_config('linkora_test.created_org',public.create_organization('Synthetic setup organization',null,null,null,'USD',1,'accrual','Synthetic Owner')::text,true);
select is((select role::text from public.organization_members where org_id=current_setting('linkora_test.created_org')::uuid and user_id=current_setting('linkora_test.maker')::uuid),'owner','organization setup assigns the authenticated creator as owner');
select ok((select count(*)>=30 from public.accounts where org_id=current_setting('linkora_test.created_org')::uuid),'organization setup creates the starter chart of accounts');
select ok(not has_table_privilege('authenticated','public.receipt_attachments','insert'),'clients cannot insert receipt metadata directly');
select ok(has_function_privilege('authenticated','public.register_receipt_attachment(uuid,uuid,text,text,text,bigint)','execute'),'authenticated uploads register metadata through validated RPC');

select is((select count(*)::integer from public.accounts where org_id=current_setting('linkora_test.org_b')::uuid),0,'RLS hides another organization chart of accounts');
select is((select cash_flow_class from public.accounts where id=current_setting('linkora_test.revenue')::uuid),'operating','new revenue accounts default to operating cash-flow classification');
select is((select reporting_class from public.accounts where id=current_setting('linkora_test.starter_contra')::uuid),'accumulated_depreciation','starter chart contra-asset account is classified automatically');
select set_config('linkora_test.department',public.create_department(current_setting('linkora_test.org_a')::uuid,'OPS','Operations','Synthetic test department')::text,true);
select is((select code from public.departments where id=current_setting('linkora_test.department')::uuid),'OPS','authorized member creates a tenant-scoped department');
select is(exists(select 1 from public.audit_logs where org_id=current_setting('linkora_test.org_a')::uuid and entity_type='departments' and entity_id=current_setting('linkora_test.department')::uuid and action='insert'),true,'department creation is audited');
select set_config('linkora_test.project',public.create_project(current_setting('linkora_test.org_a')::uuid,'PRJ-1','Implementation','Synthetic test project',current_date,null)::text,true);
select is((select code from public.projects where id=current_setting('linkora_test.project')::uuid),'PRJ-1','authorized member creates a tenant-scoped project');
select throws_ok($$select public.create_journal_entry_draft(current_setting('linkora_test.org_b')::uuid,current_date,'CROSS-DIM','Cross-organization dimension','USD',1,'general',jsonb_build_array(jsonb_build_object('account_id',current_setting('linkora_test.org_b_cash'),'debit','1','credit','0','department_id',current_setting('linkora_test.department')),jsonb_build_object('account_id',current_setting('linkora_test.org_b_bank'),'debit','0','credit','1')))$$,
  'Choose an active department from this organization','journal lines cannot reference another organization department');
select throws_ok(
  $$select public.create_journal_entry_draft(current_setting('linkora_test.org_b')::uuid,current_date,null,'cross-tenant attempt','USD',1,'general','[]'::jsonb)$$,
  'Not authorized to create journal entries','RPC refuses journal creation for another organization');
select throws_ok(
  $$insert into public.journal_entries(org_id,entry_date,description,status,created_by) values(current_setting('linkora_test.org_a')::uuid,current_date,'direct post bypass','posted',current_setting('linkora_test.maker')::uuid)$$,
  'Journal entries must be created as drafts','direct inserts cannot skip the journal workflow');

select set_config('linkora_test.entry',public.create_journal_entry_draft(
  current_setting('linkora_test.org_a')::uuid,current_date,'TEST-001','Synthetic test revenue','USD',1,'general',
  jsonb_build_array(
    jsonb_build_object('account_id',current_setting('linkora_test.cash'),'debit','25.00','credit','0','department_id',current_setting('linkora_test.department'),'project_id',current_setting('linkora_test.project')),
    jsonb_build_object('account_id',current_setting('linkora_test.revenue'),'debit','0','credit','25.00','department_id',current_setting('linkora_test.department'),'project_id',current_setting('linkora_test.project'))
  )
)::text,true);
select is((select count(*)::integer from public.journal_entry_lines_with_dimensions_exact(current_setting('linkora_test.entry')::uuid) where department_id=current_setting('linkora_test.department')::uuid and project_id=current_setting('linkora_test.project')::uuid),2,'journal draft preserves per-line department and project allocations');
select throws_ok($$select public.set_department_active(current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.department')::uuid,false)$$,
  'Remove this department from draft journal entries before deactivating it','database prevents deactivating a dimension used on a draft');
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.entry')::uuid),'draft','new accounting entry starts as a draft');
select throws_ok($$select public.queue_journal_entry(current_setting('linkora_test.entry')::uuid)$$,
  'Maker-checker: the creator cannot queue their own entry','creator cannot queue their own journal entry');
select public.submit_journal_entry(current_setting('linkora_test.entry')::uuid);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.entry')::uuid),'submitted','maker submission moves draft to submitted');

select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.entry')::uuid);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.entry')::uuid),'pending_approval','authorized checker queues entry');
select public.approve_journal_entry(current_setting('linkora_test.entry')::uuid);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.entry')::uuid),'approved','different authorized member approves entry');
select public.post_journal_entry(current_setting('linkora_test.entry')::uuid);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.entry')::uuid),'posted','approved journal posts atomically');
select is((select balance from public.dimension_activity_exact(current_setting('linkora_test.org_a')::uuid,current_date,current_date,'department',current_setting('linkora_test.department')::uuid) where type='revenue'),'25.0000','department revenue report uses only its posted functional-currency activity');
select is((select balance from public.dimension_activity_exact(current_setting('linkora_test.org_a')::uuid,current_date,current_date,'project',current_setting('linkora_test.project')::uuid) where type='revenue'),'25.0000','project profitability report uses its posted functional-currency revenue');
select is((select value from public.financial_ratios_exact(current_setting('linkora_test.org_a')::uuid,current_date,current_date,current_date) where ratio_key='net_profit_margin'),'100.0000','net profit margin derives from posted revenue and expenses');
select is((select value from public.financial_ratios_exact(current_setting('linkora_test.org_a')::uuid,current_date,current_date,current_date) where ratio_key='expense_to_income'),'0.0000','expense ratio derives from posted period expenses');
select is((select count(*)::integer from public.financial_ratios_exact(current_setting('linkora_test.org_a')::uuid,current_date,current_date,current_date)),7,'ratio report returns the defined seven ledger-based measures');
select throws_ok($$select * from public.financial_ratios_exact(current_setting('linkora_test.org_b')::uuid,current_date,current_date,current_date)$$,
  'Not authorized to view this organization','financial ratio RPC rejects cross-organization reads');
select is((select amount from public.cash_flow_statement_exact(current_setting('linkora_test.org_a')::uuid,current_date,current_date) where section='operating'),'25.0000','cash flow classifies cash receipts by their operating counter-account');
select is((select amount from public.cash_flow_statement_exact(current_setting('linkora_test.org_a')::uuid,current_date,current_date) where section='net_change'),'25.0000','cash flow net change reflects posted functional-currency movements');
select is((select amount from public.cash_flow_statement_exact(current_setting('linkora_test.org_a')::uuid,current_date,current_date) where section='ledger_cash_movement'),'25.0000','cash flow reconciles to cash and bank ledger movement');
select is((select amount from public.cash_flow_statement_exact(current_setting('linkora_test.org_a')::uuid,current_date,current_date) where section='reconciliation_difference'),'0.0000','cash flow classification and the General Ledger reconcile exactly');

select is(
 (select sum(debit::numeric) from public.trial_balance_as_of_exact(current_setting('linkora_test.org_a')::uuid,current_date)),
 (select sum(credit::numeric) from public.trial_balance_as_of_exact(current_setting('linkora_test.org_a')::uuid,current_date)),
 'posted synthetic trial balance has equal debits and credits');
select is(
 (select cash_balance::numeric from public.financial_summary_exact(current_setting('linkora_test.org_a')::uuid,current_date,current_date,current_date)),
 25::numeric,'explicit cash classification reports the posted balance');
select ok(exists(select 1 from public.audit_logs where org_id=current_setting('linkora_test.org_a')::uuid and entity_id=current_setting('linkora_test.entry')::uuid and action='journal_posted'),
 'posting transition is captured in the organization audit trail');

select set_config('linkora_test.reversal',public.reverse_journal_entry(current_setting('linkora_test.entry')::uuid,current_date,'Synthetic reversal test')::text,true);
select public.submit_journal_entry(current_setting('linkora_test.reversal')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.reversal')::uuid);
select public.approve_journal_entry(current_setting('linkora_test.reversal')::uuid);
select public.post_journal_entry(current_setting('linkora_test.reversal')::uuid);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.entry')::uuid),'reversed','posting reversal marks original entry reversed');
select is(
 (select sum(debit::numeric)+sum(credit::numeric) from public.trial_balance_as_of_exact(current_setting('linkora_test.org_a')::uuid,current_date)),
 0::numeric,'posted reversal restores the original trial balance to zero');

select set_config('linkora_test.transfer_bad',public.create_journal_entry_draft(
 current_setting('linkora_test.org_a')::uuid,current_date,'TEST-BANK-BAD','Invalid split bank transfer','USD',1,'bank_transfer',
 jsonb_build_array(
   jsonb_build_object('account_id',current_setting('linkora_test.cash'),'debit','10.00','credit','0'),
   jsonb_build_object('account_id',current_setting('linkora_test.bank'),'debit','0','credit','5.00'),
   jsonb_build_object('account_id',current_setting('linkora_test.bank'),'debit','0','credit','5.00')
 )
)::text,true);
select throws_ok($$select public.submit_journal_entry(current_setting('linkora_test.transfer_bad')::uuid)$$,
 'A bank transfer must contain exactly two lines, one debit and one credit','database rejects split or multi-line internal transfers');

select set_config('linkora_test.transfer_non_cash',public.create_journal_entry_draft(
 current_setting('linkora_test.org_a')::uuid,current_date,'TEST-BANK-AR','Invalid receivable transfer','USD',1,'bank_transfer',
 jsonb_build_array(
   jsonb_build_object('account_id',current_setting('linkora_test.cash'),'debit','10.00','credit','0'),
   jsonb_build_object('account_id',current_setting('linkora_test.receivable'),'debit','0','credit','10.00')
 )
)::text,true);
select throws_ok($$select public.submit_journal_entry(current_setting('linkora_test.transfer_non_cash')::uuid)$$,
 'Internal transfers may only use cash or bank accounts','database rejects receivable accounts in internal transfers');

select set_config('linkora_test.transfer_unclassified',public.create_journal_entry_draft(
 current_setting('linkora_test.org_a')::uuid,current_date,'TEST-BANK-UNCLASSIFIED','Invalid unclassified asset transfer','USD',1,'bank_transfer',
 jsonb_build_array(
   jsonb_build_object('account_id',current_setting('linkora_test.cash'),'debit','7.00','credit','0'),
   jsonb_build_object('account_id',current_setting('linkora_test.unclassified'),'debit','0','credit','7.00')
 )
)::text,true);
select throws_ok($$select public.submit_journal_entry(current_setting('linkora_test.transfer_unclassified')::uuid)$$,
 'Internal transfers may only use cash or bank accounts','database rejects unclassified asset accounts in internal transfers');

select set_config('linkora_test.transfer_good',public.create_journal_entry_draft(
 current_setting('linkora_test.org_a')::uuid,current_date,'TEST-BANK-GOOD','Valid internal bank transfer','USD',1,'bank_transfer',
 jsonb_build_array(
   jsonb_build_object('account_id',current_setting('linkora_test.cash'),'debit','10.00','credit','0'),
   jsonb_build_object('account_id',current_setting('linkora_test.bank'),'debit','0','credit','10.00')
 )
)::text,true);
select public.submit_journal_entry(current_setting('linkora_test.transfer_good')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.transfer_good')::uuid);
select public.approve_journal_entry(current_setting('linkora_test.transfer_good')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select public.post_journal_entry(current_setting('linkora_test.transfer_good')::uuid);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.transfer_good')::uuid),'posted','valid two-account internal transfer posts through maker-checker workflow');
select is((select income::numeric from public.financial_summary_exact(current_setting('linkora_test.org_a')::uuid,current_date,current_date,current_date)),0::numeric,'internal transfer does not create revenue');
select is((select expenses::numeric from public.financial_summary_exact(current_setting('linkora_test.org_a')::uuid,current_date,current_date,current_date)),0::numeric,'internal transfer does not create an expense');
select is((select cash_balance::numeric from public.financial_summary_exact(current_setting('linkora_test.org_a')::uuid,current_date,current_date,current_date)),-10::numeric,'internal transfer reduces the source cash account');
select is((select bank_balance::numeric from public.financial_summary_exact(current_setting('linkora_test.org_a')::uuid,current_date,current_date,current_date)),10::numeric,'internal transfer increases the destination bank account');
select set_config('linkora_test.bank_line',(select id::text from public.journal_lines where entry_id=current_setting('linkora_test.transfer_good')::uuid and account_id=current_setting('linkora_test.bank')::uuid and debit=10),true);
select set_config('linkora_test.statement_import',public.import_bank_statement(
 current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.bank')::uuid,'synthetic-bank.csv',
 current_date,current_date,'0.0000','10.0000',
 jsonb_build_array(
   jsonb_build_object('date',current_date::text,'description','Synthetic mismatch row','reference','BANK-000','amount','9.9900'),
   jsonb_build_object('date',current_date::text,'description','Synthetic bank receipt','reference','BANK-001','amount','10.0000')
 )
)::text,true);
select set_config('linkora_test.statement_row',(select id::text from public.bank_statement_rows where import_id=current_setting('linkora_test.statement_import')::uuid and row_number=2),true);
select is((select count(*)::integer from public.bank_statement_rows where import_id=current_setting('linkora_test.statement_import')::uuid),2,'CSV import creates isolated statement rows');
select is((select amount from public.bank_statement_rows_exact where id=current_setting('linkora_test.statement_row')::uuid),'10.0000','statement row preserves NUMERIC precision in its read model');
select ok(exists(select 1 from public.audit_logs where org_id=current_setting('linkora_test.org_a')::uuid and entity_type='bank_statement_imports' and entity_id=current_setting('linkora_test.statement_import')::uuid and action='insert'),'statement imports are audited');
select throws_ok($$select public.match_bank_statement_row((select id from public.bank_statement_rows where import_id=current_setting('linkora_test.statement_import')::uuid and row_number=1),current_setting('linkora_test.bank_line')::uuid)$$,
 'Statement amount does not equal the signed functional-currency ledger amount','database rejects a statement-to-ledger amount mismatch');
select public.match_bank_statement_row(current_setting('linkora_test.statement_row')::uuid,current_setting('linkora_test.bank_line')::uuid);
select is((select matched_journal_line_id::text from public.bank_statement_rows where id=current_setting('linkora_test.statement_row')::uuid),current_setting('linkora_test.bank_line'),'statement row matches the exact posted bank ledger line');
select ok(exists(select 1 from public.audit_logs where org_id=current_setting('linkora_test.org_a')::uuid and entity_type='bank_statement_rows' and entity_id=current_setting('linkora_test.statement_row')::uuid and action='update'),'statement reconciliation changes are audited');
select is((select statement_calculated_closing from public.bank_reconciliation_report_exact(current_setting('linkora_test.statement_import')::uuid)),'19.9900','reconciliation report calculates closing balance from opening balance and imported activity');
select is((select closing_difference from public.bank_reconciliation_report_exact(current_setting('linkora_test.statement_import')::uuid)),'0.0000','reconciliation report compares closing balance to the General Ledger');
select is((select statement_activity_difference from public.bank_reconciliation_report_exact(current_setting('linkora_test.statement_import')::uuid)),'-9.9900','reconciliation report identifies statement balance versus imported row difference');
select is((select unmatched_activity_difference from public.bank_reconciliation_report_exact(current_setting('linkora_test.statement_import')::uuid)),'9.9900','reconciliation report calculates unmatched statement activity difference');
select is((select is_reconciled from public.bank_reconciliation_report_exact(current_setting('linkora_test.statement_import')::uuid)),false,'bank statement remains unreconciled while an amount difference exists');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.outsider'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.outsider'),'role','authenticated','aud','authenticated')::text,true);
select is((select count(*)::integer from public.bank_statement_rows where org_id=current_setting('linkora_test.org_a')::uuid),0,'RLS hides statement data from a different organization');
select throws_ok($$select public.import_bank_statement(current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.bank')::uuid,'cross-tenant.csv',current_date,current_date,'0','1',jsonb_build_array(jsonb_build_object('date',current_date::text,'description','Unauthorized','reference',null,'amount','1.00')))$$,
 'Not authorized to import bank statements','database rejects cross-organization bank statement imports');
select set_config('linkora_test.org_b_entry',public.create_journal_entry_draft(
 current_setting('linkora_test.org_b')::uuid,current_date,'TEST-B-001','Synthetic reconciled bank transfer','USD',1,'bank_transfer',
 jsonb_build_array(
   jsonb_build_object('account_id',current_setting('linkora_test.org_b_bank'),'debit','25.00','credit','0'),
   jsonb_build_object('account_id',current_setting('linkora_test.org_b_cash'),'debit','0','credit','25.00')
 )
)::text,true);
select public.submit_journal_entry(current_setting('linkora_test.org_b_entry')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.org_b_entry')::uuid);
select public.approve_journal_entry(current_setting('linkora_test.org_b_entry')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.outsider'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.outsider'),'role','authenticated','aud','authenticated')::text,true);
select public.post_journal_entry(current_setting('linkora_test.org_b_entry')::uuid);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.org_b_entry')::uuid),'posted','separate organization bank entry follows maker-checker posting');
select set_config('linkora_test.org_b_bank_line',(select id::text from public.journal_lines where entry_id=current_setting('linkora_test.org_b_entry')::uuid and account_id=current_setting('linkora_test.org_b_bank')::uuid and debit=25),true);
select set_config('linkora_test.org_b_import',public.import_bank_statement(
 current_setting('linkora_test.org_b')::uuid,current_setting('linkora_test.org_b_bank')::uuid,'synthetic-balanced-bank.csv',
 current_date,current_date,'0.0000','25.0000',
 jsonb_build_array(jsonb_build_object('date',current_date::text,'description','Synthetic bank settlement','reference','B-001','amount','25.0000'))
)::text,true);
select set_config('linkora_test.org_b_row',(select id::text from public.bank_statement_rows where import_id=current_setting('linkora_test.org_b_import')::uuid),true);
select public.match_bank_statement_row(current_setting('linkora_test.org_b_row')::uuid,current_setting('linkora_test.org_b_bank_line')::uuid);
select is((select is_reconciled from public.bank_reconciliation_report_exact(current_setting('linkora_test.org_b_import')::uuid)),true,'complete statement and ledger activity reconcile to opening and closing balances');
select is((select opening_difference from public.bank_reconciliation_report_exact(current_setting('linkora_test.org_b_import')::uuid)),'0.0000','fully reconciled statement has a matching opening balance');
select is((select closing_difference from public.bank_reconciliation_report_exact(current_setting('linkora_test.org_b_import')::uuid)),'0.0000','fully reconciled statement has a matching closing balance');
select is((select unmatched_activity_difference from public.bank_reconciliation_report_exact(current_setting('linkora_test.org_b_import')::uuid)),'0.0000','fully matched statement activity difference is zero');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);

select set_config('linkora_test.customer',public.create_financial_party(current_setting('linkora_test.org_a')::uuid,'customer','Synthetic Customer','customer@linkora.test',null)::text,true);
select is((select party_type from public.financial_parties where id=current_setting('linkora_test.customer')::uuid),'customer','customer record is created through the authorized RPC');
select set_config('linkora_test.tax_code',public.create_tax_code(current_setting('linkora_test.org_a')::uuid,'VAT-10','Synthetic VAT','sales',10,current_setting('linkora_test.tax_liability')::uuid,null,current_date,null)::text,true);
select is((select rate from public.tax_codes where id=current_setting('linkora_test.tax_code')::uuid),10::numeric,'organization creates an explicit configurable tax code');
select throws_ok($$update public.tax_codes set rate=0 where id=current_setting('linkora_test.tax_code')::uuid$$,
  'permission denied for table tax_codes','authenticated users cannot rewrite an established tax policy');
select is((select count(*)::integer from public.tax_codes where org_id=current_setting('linkora_test.org_b')::uuid),0,'tax code RLS hides another organization tax settings');
select set_config('linkora_test.purchase_tax_code',public.create_tax_code(current_setting('linkora_test.org_a')::uuid,'VAT-IN-5','Synthetic recoverable VAT','purchases',5,null,current_setting('linkora_test.unclassified')::uuid,current_date,null)::text,true);
select is((select purchase_account_id from public.tax_codes where id=current_setting('linkora_test.purchase_tax_code')::uuid),current_setting('linkora_test.unclassified')::uuid,'purchase tax is linked to the configured tenant asset account');
select set_config('linkora_test.supplier',public.create_financial_party(current_setting('linkora_test.org_a')::uuid,'supplier','Synthetic Supplier',null,null)::text,true);
select throws_ok($$select public.create_financial_document_draft(current_setting('linkora_test.org_a')::uuid,'invoice',current_setting('linkora_test.customer')::uuid,'INV-WRONG-TAX',current_date,current_date,current_setting('linkora_test.receivable')::uuid,jsonb_build_array(jsonb_build_object('account_id',current_setting('linkora_test.revenue'),'amount','1','description','Wrong tax scope','tax_code_id',current_setting('linkora_test.purchase_tax_code'))))$$,
 'Tax code is not valid for this document type','purchase-only tax code cannot be applied to a sales invoice');
select set_config('linkora_test.bill',public.create_financial_document_draft(current_setting('linkora_test.org_a')::uuid,'bill',current_setting('linkora_test.supplier')::uuid,'BILL-TEST-001',current_date,current_date,current_setting('linkora_test.payable')::uuid,jsonb_build_array(jsonb_build_object('account_id',current_setting('linkora_test.expense'),'amount','40.0000','description','Synthetic supplies','tax_code_id',current_setting('linkora_test.purchase_tax_code'))) )::text,true);
select is((select tax_amount from public.financial_document_lines where document_id=current_setting('linkora_test.bill')::uuid),'2.0000','purchase tax is calculated as a recoverable amount');
select is((select total from public.financial_documents_exact where id=current_setting('linkora_test.bill')::uuid),'42.0000','supplier bill gross total includes recoverable tax');
select set_config('linkora_test.invoice',public.create_financial_document_draft(
 current_setting('linkora_test.org_a')::uuid,'invoice',current_setting('linkora_test.customer')::uuid,'INV-TEST-001',current_date,current_date,
 current_setting('linkora_test.receivable')::uuid,
 jsonb_build_array(jsonb_build_object('account_id',current_setting('linkora_test.revenue'),'amount','100.0000','description','Synthetic consulting service','tax_code_id',current_setting('linkora_test.tax_code')))
)::text,true);
select is((select status from public.financial_documents where id=current_setting('linkora_test.invoice')::uuid),'draft','invoice begins as an editable draft');
select is((select tax_amount from public.financial_document_lines where document_id=current_setting('linkora_test.invoice')::uuid),'10.0000','tax amount is calculated and snapshotted with NUMERIC precision');
select is((select total from public.financial_documents_exact where id=current_setting('linkora_test.invoice')::uuid),'110.0000','invoice gross total includes line tax');
select set_config('linkora_test.invoice_entry',public.submit_financial_document(current_setting('linkora_test.invoice')::uuid)::text,true);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.invoice_entry')::uuid),'submitted','invoice submission creates a journal in review');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.invoice_entry')::uuid);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.invoice_entry')::uuid),'pending_approval','invoice journal enters approval queue');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select throws_ok($$select public.approve_journal_entry(current_setting('linkora_test.invoice_entry')::uuid)$$,
 'Maker-checker: the creator cannot approve their own entry','invoice maker cannot approve their own journal');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.approve_journal_entry(current_setting('linkora_test.invoice_entry')::uuid);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.invoice_entry')::uuid),'approved','authorized checker approves invoice journal');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select public.post_journal_entry(current_setting('linkora_test.invoice_entry')::uuid);
select is((select status from public.financial_documents where id=current_setting('linkora_test.invoice')::uuid),'issued','invoice issues only after journal posting');
select is((select credit from public.journal_lines where entry_id=current_setting('linkora_test.invoice_entry')::uuid and account_id=current_setting('linkora_test.tax_liability')::uuid),'10.0000','posted invoice credits the configured tax liability account');
select is((select sales_tax from public.tax_activity_exact(current_setting('linkora_test.org_a')::uuid,current_date,current_date) where tax_code_id=current_setting('linkora_test.tax_code')::uuid),'10.0000','tax activity report reflects posted invoice tax');
select set_config('linkora_test.payment_entry',public.record_financial_document_payment(
 current_setting('linkora_test.invoice')::uuid,current_date,current_setting('linkora_test.cash')::uuid,'40.2500','RCPT-001'
)::text,true);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.payment_entry')::uuid),'submitted','customer payment creates a submitted journal draft');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.payment_entry')::uuid);
select public.approve_journal_entry(current_setting('linkora_test.payment_entry')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select public.post_journal_entry(current_setting('linkora_test.payment_entry')::uuid);
select is((select paid from public.financial_documents_exact where id=current_setting('linkora_test.invoice')::uuid),'40.2500','invoice payment counts only after posting and retains decimal precision');
select is((select outstanding from public.financial_documents_exact where id=current_setting('linkora_test.invoice')::uuid),'69.7500','invoice outstanding balance includes tax and remains exact after partial payment');
select is((select aging_bucket from public.financial_aging_exact(current_setting('linkora_test.org_a')::uuid,current_date) where document_id=current_setting('linkora_test.invoice')::uuid),'current','aging report includes the invoice in the current bucket when not overdue');
select is((select outstanding from public.financial_aging_exact(current_setting('linkora_test.org_a')::uuid,current_date) where document_id=current_setting('linkora_test.invoice')::uuid),'69.7500','aging report uses the exact posted tax-inclusive outstanding amount');
select ok(exists(select 1 from public.audit_logs where org_id=current_setting('linkora_test.org_a')::uuid and entity_type='financial_documents' and entity_id=current_setting('linkora_test.invoice')::uuid and action='update'),'invoice state transitions are audited');
select set_config('linkora_test.rejected_payment_entry',public.record_financial_document_payment(current_setting('linkora_test.invoice')::uuid,current_date,current_setting('linkora_test.cash')::uuid,'5.0000','RCPT-REJECT')::text,true);
select set_config('linkora_test.rejected_payment',(select id::text from public.financial_document_payments where journal_entry_id=current_setting('linkora_test.rejected_payment_entry')::uuid),true);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.rejected_payment_entry')::uuid);
select public.reject_journal_entry(current_setting('linkora_test.rejected_payment_entry')::uuid,'Correct the receipt date and reference');
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.rejected_payment_entry')::uuid),'draft','rejected payment returns to a draft for correction');
select is((select rejection_reason from public.journal_entries where id=current_setting('linkora_test.rejected_payment_entry')::uuid),'Correct the receipt date and reference','payment rejection reason remains visible for the maker');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select public.correct_and_resubmit_financial_document_payment(current_setting('linkora_test.rejected_payment')::uuid,current_date,current_setting('linkora_test.bank')::uuid,'6.2500','RCPT-CORRECTED');
select is((select amount::text||':'||reference from public.financial_document_payments where id=current_setting('linkora_test.rejected_payment')::uuid),'6.2500:RCPT-CORRECTED','payment correction updates the reserved amount and reference');
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.rejected_payment_entry')::uuid),'submitted','corrected payment resubmits its existing journal');
select is((select sum(debit)=sum(credit) and sum(debit)=6.2500 from public.journal_lines where entry_id=current_setting('linkora_test.rejected_payment_entry')::uuid),true,'corrected payment journal remains balanced at exact NUMERIC precision');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.outsider'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.outsider'),'role','authenticated','aud','authenticated')::text,true);
select throws_ok($$select public.correct_and_resubmit_financial_document_payment(current_setting('linkora_test.rejected_payment')::uuid,current_date,current_setting('linkora_test.cash')::uuid,'7.0000','OTHER')$$,
 'Only the payment creator may correct it','another organization member cannot correct the payment creator record');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select set_config('linkora_test.invoice_reversal',public.reverse_journal_entry(current_setting('linkora_test.invoice_entry')::uuid,current_date,'Synthetic correction test')::text,true);
select public.submit_journal_entry(current_setting('linkora_test.invoice_reversal')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.invoice_reversal')::uuid);
select public.approve_journal_entry(current_setting('linkora_test.invoice_reversal')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select throws_ok($$select public.post_journal_entry(current_setting('linkora_test.invoice_reversal')::uuid)$$,
 'An invoice or bill with active payments cannot be reversed','database prevents reversal while a posted payment remains active');
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.invoice_entry')::uuid),'posted','blocked invoice reversal leaves the original accounting entry posted');
select is((select status from public.financial_documents where id=current_setting('linkora_test.invoice')::uuid),'issued','blocked invoice reversal leaves receivable document active');

select set_config('linkora_test.acquisition_entry',public.create_journal_entry_draft(
 current_setting('linkora_test.org_a')::uuid,current_date,'FA-ACQ-001','Synthetic fixed asset acquisition','USD',1,'general',
 jsonb_build_array(
   jsonb_build_object('account_id',current_setting('linkora_test.fixed_asset_account'),'debit','1200.0000','credit','0'),
   jsonb_build_object('account_id',current_setting('linkora_test.cash'),'debit','0','credit','1200.0000')
 )
)::text,true);
select public.submit_journal_entry(current_setting('linkora_test.acquisition_entry')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.acquisition_entry')::uuid);
select public.approve_journal_entry(current_setting('linkora_test.acquisition_entry')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select public.post_journal_entry(current_setting('linkora_test.acquisition_entry')::uuid);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.acquisition_entry')::uuid),'posted','fixed-asset acquisition posts through maker-checker');
select set_config('linkora_test.fixed_asset',public.register_fixed_asset(
 current_setting('linkora_test.org_a')::uuid,'FA-001','Synthetic equipment',null,current_date,current_date,'1200.0000','0.0000',12,
 current_setting('linkora_test.fixed_asset_account')::uuid,current_setting('linkora_test.accum_depreciation_account')::uuid,
 current_setting('linkora_test.depreciation_expense_account')::uuid,current_setting('linkora_test.acquisition_entry')::uuid
)::text,true);
select is((select cost from public.fixed_assets_exact where id=current_setting('linkora_test.fixed_asset')::uuid),'1200.0000','asset register preserves exact acquisition cost');
select is((select count(*)::integer from public.fixed_assets where acquisition_entry_id=current_setting('linkora_test.acquisition_entry')::uuid),1,'asset remains traceably linked to its posted acquisition entry');
select set_config('linkora_test.acquisition_reversal',public.reverse_journal_entry(current_setting('linkora_test.acquisition_entry')::uuid,current_date,'Synthetic fixed asset reversal guard')::text,true);
select public.submit_journal_entry(current_setting('linkora_test.acquisition_reversal')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.acquisition_reversal')::uuid);
select public.approve_journal_entry(current_setting('linkora_test.acquisition_reversal')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select throws_ok($$select public.post_journal_entry(current_setting('linkora_test.acquisition_reversal')::uuid)$$,
 'A fixed-asset acquisition cannot be reversed while assets are registered','database blocks reversal of a registered fixed-asset acquisition');
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.acquisition_entry')::uuid),'posted','blocked asset acquisition reversal preserves the posted source entry');
select set_config('linkora_test.depreciation_entry',public.create_fixed_asset_depreciation_draft(current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.month_end')::date)::text,true);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.depreciation_entry')::uuid),'submitted','straight-line depreciation creates a submitted journal draft');
select is((select sum(amount) from public.asset_depreciation_lines where run_id=(select id from public.asset_depreciation_runs where journal_entry_id=current_setting('linkora_test.depreciation_entry')::uuid)),'100.0000','monthly depreciation uses exact straight-line arithmetic');
select throws_ok($$select public.create_fixed_asset_depreciation_draft(current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.month_end')::date)$$,
 'No active, not-yet-depreciated fixed assets are eligible for this month','database prevents duplicate depreciation for the same asset period');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.depreciation_entry')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select throws_ok($$select public.approve_journal_entry(current_setting('linkora_test.depreciation_entry')::uuid)$$,
 'Maker-checker: the creator cannot approve their own entry','depreciation maker cannot approve their own journal');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.approve_journal_entry(current_setting('linkora_test.depreciation_entry')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select public.post_journal_entry(current_setting('linkora_test.depreciation_entry')::uuid);
select is((select accumulated_depreciation from public.fixed_assets_exact where id=current_setting('linkora_test.fixed_asset')::uuid),'100.0000','posted depreciation updates exact accumulated depreciation');
select is((select net_book_value from public.fixed_assets_exact where id=current_setting('linkora_test.fixed_asset')::uuid),'1100.0000','asset register reports exact net book value');
select is((select status from public.asset_depreciation_runs where journal_entry_id=current_setting('linkora_test.depreciation_entry')::uuid),'posted','depreciation run becomes posted only with its journal');

select set_config('linkora_test.disposal_entry',public.create_fixed_asset_disposal_draft(
 current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.fixed_asset')::uuid,current_setting('linkora_test.month_end')::date,
 '1000.0000',current_setting('linkora_test.cash')::uuid,null,current_setting('linkora_test.expense')::uuid
)::text,true);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.disposal_entry')::uuid),'submitted','fixed-asset disposal submits its balanced journal for review');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.outsider'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.outsider'),'role','authenticated','aud','authenticated')::text,true);
select is((select count(*)::integer from public.fixed_asset_disposals),'0','another organization cannot read fixed-asset disposal records');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select is((select sum(debit)::text from public.journal_lines where entry_id=current_setting('linkora_test.disposal_entry')::uuid),'1200.0000','disposal debits proceeds, accumulated depreciation, and loss at carrying value');
select is((select sum(credit)::text from public.journal_lines where entry_id=current_setting('linkora_test.disposal_entry')::uuid),'1200.0000','disposal credits the original asset cost exactly');
select is((select debit from public.journal_lines where entry_id=current_setting('linkora_test.disposal_entry')::uuid and account_id=current_setting('linkora_test.expense')::uuid),'100.0000','disposal recognizes the exact loss against net book value');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.disposal_entry')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select throws_ok($$select public.approve_journal_entry(current_setting('linkora_test.disposal_entry')::uuid)$$,
 'Maker-checker: you cannot approve your own entry','disposal maker cannot approve their own journal');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.approve_journal_entry(current_setting('linkora_test.disposal_entry')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select public.post_journal_entry(current_setting('linkora_test.disposal_entry')::uuid);
select is((select status from public.fixed_assets where id=current_setting('linkora_test.fixed_asset')::uuid),'disposed','asset status changes only after the disposal journal posts');
select is((select status from public.fixed_asset_disposals where journal_entry_id=current_setting('linkora_test.disposal_entry')::uuid),'posted','disposal record follows the posted journal');
select set_config('linkora_test.disposal_reversal',public.reverse_journal_entry(current_setting('linkora_test.disposal_entry')::uuid,current_setting('linkora_test.month_end')::date,'Synthetic disposal reversal test')::text,true);
select public.submit_journal_entry(current_setting('linkora_test.disposal_reversal')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.disposal_reversal')::uuid);
select public.approve_journal_entry(current_setting('linkora_test.disposal_reversal')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select public.post_journal_entry(current_setting('linkora_test.disposal_reversal')::uuid);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.disposal_entry')::uuid),'reversed','posted reversal marks the disposal journal reversed');
select is((select status from public.fixed_assets where id=current_setting('linkora_test.fixed_asset')::uuid),'active','posted reversal restores the asset register to active');
select is((select status from public.fixed_asset_disposals where journal_entry_id=current_setting('linkora_test.disposal_entry')::uuid),'reversed','reversal preserves and marks disposal history');
select ok(exists(select 1 from public.audit_logs where org_id=current_setting('linkora_test.org_a')::uuid and entity_type='fixed_asset_disposals' and entity_id=(select id from public.fixed_asset_disposals where journal_entry_id=current_setting('linkora_test.disposal_entry')::uuid) and action='update'),'asset disposal lifecycle updates are audited');
select set_config('linkora_test.gain_disposal_entry',public.create_fixed_asset_disposal_draft(
 current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.fixed_asset')::uuid,current_setting('linkora_test.month_end')::date,
 '1200.0000',current_setting('linkora_test.cash')::uuid,current_setting('linkora_test.revenue')::uuid,null
)::text,true);
select is((select credit from public.journal_lines where entry_id=current_setting('linkora_test.gain_disposal_entry')::uuid and account_id=current_setting('linkora_test.revenue')::uuid),'100.0000','disposal recognizes exact gain above the carrying value');
select is((select count(*)::integer from public.journal_lines where entry_id=current_setting('linkora_test.gain_disposal_entry')::uuid and account_id=current_setting('linkora_test.expense')::uuid),0,'gain disposal does not create a loss line');

select set_config('linkora_test.fx_entry',public.create_journal_entry_draft(
 current_setting('linkora_test.org_a')::uuid,current_date,'FX-001','Synthetic manually rated EUR journal','EUR','1.23456789','general',
 jsonb_build_array(
   jsonb_build_object('account_id',current_setting('linkora_test.cash'),'debit','100.0000','credit','0'),
   jsonb_build_object('account_id',current_setting('linkora_test.revenue'),'debit','0','credit','100.0000')
 )
)::text,true);
select public.submit_journal_entry(current_setting('linkora_test.fx_entry')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.fx_entry')::uuid);
select public.approve_journal_entry(current_setting('linkora_test.fx_entry')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select public.post_journal_entry(current_setting('linkora_test.fx_entry')::uuid);
select is((select exchange_rate from public.journal_exchange_rate_exact(current_setting('linkora_test.fx_entry')::uuid)),'1.23456789','journal stores and reads the exact manual exchange rate');
select is((select sum(base_debit)::text from public.journal_lines where entry_id=current_setting('linkora_test.fx_entry')::uuid),'123.4568','functional-currency journal amount uses NUMERIC rounding at four places');

select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select set_config('linkora_test.budget',public.create_budget_draft(
 current_setting('linkora_test.org_a')::uuid,'Synthetic monthly budget',
 current_setting('linkora_test.month_start')::date,current_setting('linkora_test.month_end')::date,
 jsonb_build_array(jsonb_build_object('account_id',current_setting('linkora_test.expense'),'period_start',current_setting('linkora_test.month_start'),'amount','100.0000'))
)::text,true);
select is((select status from public.budgets where id=current_setting('linkora_test.budget')::uuid),'draft'::text,'budget starts as a draft');
select throws_ok($$select public.approve_budget(current_setting('linkora_test.budget')::uuid)$$,
 'Maker-checker: the creator cannot approve their own budget','budget creator cannot approve own plan');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.approve_budget(current_setting('linkora_test.budget')::uuid);
select is((select status from public.budgets where id=current_setting('linkora_test.budget')::uuid),'approved'::text,'different finance manager approves the budget');
select is((select budget::numeric from public.budget_variance_exact(current_setting('linkora_test.budget')::uuid)),100::numeric,'variance report returns the planned amount exactly');
select is((select actual::numeric from public.budget_variance_exact(current_setting('linkora_test.budget')::uuid)),0::numeric,'budget actuals exclude draft entries and use posted ledger activity only');

select set_config('linkora_test.recurring_template',public.create_recurring_template(
 current_setting('linkora_test.org_a')::uuid,'Synthetic monthly service income','income','monthly',current_date,null,'50.0000',
 current_setting('linkora_test.revenue')::uuid,current_setting('linkora_test.cash')::uuid,'Synthetic recurring service receipt','REC'
)::text,true);
select is((select next_date from public.recurring_templates where id=current_setting('linkora_test.recurring_template')::uuid),current_date,'recurring income starts on its selected due date');
select set_config('linkora_test.recurring_entry',public.generate_recurring_journal_draft(current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.recurring_template')::uuid,current_date)::text,true);
select is((select entry_kind from public.journal_entries where id=current_setting('linkora_test.recurring_entry')::uuid),'income','recurring income creates the matching accounting journal kind');
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.recurring_entry')::uuid),'draft','recurring generator creates an unposted journal draft');
select is((select next_date from public.recurring_templates where id=current_setting('linkora_test.recurring_template')::uuid),(current_date+interval '1 month')::date,'next recurring date advances from the original schedule without month-end drift');
select is((select journal_entry_id from public.recurring_occurrences where template_id=current_setting('linkora_test.recurring_template')::uuid and scheduled_date=current_date),current_setting('linkora_test.recurring_entry')::uuid,'recurring occurrence links to its generated journal for auditability');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.outsider'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.outsider'),'role','authenticated','aud','authenticated')::text,true);
select throws_ok($$select public.generate_recurring_journal_draft(current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.recurring_template')::uuid,current_date)$$,
 'Not authorized to generate recurring entries','nonmember cannot generate another organization recurring journal');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);

select set_config('linkora_test.deposit_entry',public.create_journal_entry_draft(
 current_setting('linkora_test.org_a')::uuid,current_date,'DEP-001','Synthetic classified bank deposit','USD',1,'bank_deposit',
 jsonb_build_array(jsonb_build_object('account_id',current_setting('linkora_test.bank'),'debit','15.00','credit','0'),jsonb_build_object('account_id',current_setting('linkora_test.revenue'),'debit','0','credit','15.00'))
)::text,true);
select public.submit_journal_entry(current_setting('linkora_test.deposit_entry')::uuid);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.deposit_entry')::uuid),'submitted','valid bank deposit enters the normal review workflow');
select set_config('linkora_test.invalid_deposit',public.create_journal_entry_draft(
 current_setting('linkora_test.org_a')::uuid,current_date,'DEP-002','Synthetic transfer mislabeled as deposit','USD',1,'bank_deposit',
 jsonb_build_array(jsonb_build_object('account_id',current_setting('linkora_test.bank'),'debit','15.00','credit','0'),jsonb_build_object('account_id',current_setting('linkora_test.cash'),'debit','0','credit','15.00'))
)::text,true);
select throws_ok($$select public.submit_journal_entry(current_setting('linkora_test.invalid_deposit')::uuid)$$,
 'Bank movement requires one classified cash/bank leg and one non-cash/bank counter-account leg in the correct direction','database prevents relabeling an internal transfer as a deposit');
select set_config('linkora_test.withdrawal_entry',public.create_journal_entry_draft(
 current_setting('linkora_test.org_a')::uuid,current_date,'WDR-001','Synthetic classified bank withdrawal','USD',1,'bank_withdrawal',
 jsonb_build_array(jsonb_build_object('account_id',current_setting('linkora_test.expense'),'debit','12.00','credit','0'),jsonb_build_object('account_id',current_setting('linkora_test.bank'),'debit','0','credit','12.00'))
)::text,true);
select public.submit_journal_entry(current_setting('linkora_test.withdrawal_entry')::uuid);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.withdrawal_entry')::uuid),'submitted','valid bank withdrawal enters the normal review workflow');
select set_config('linkora_test.invalid_withdrawal',public.create_journal_entry_draft(
 current_setting('linkora_test.org_a')::uuid,current_date,'WDR-002','Synthetic withdrawal with reversed legs','USD',1,'bank_withdrawal',
 jsonb_build_array(jsonb_build_object('account_id',current_setting('linkora_test.expense'),'debit','0','credit','12.00'),jsonb_build_object('account_id',current_setting('linkora_test.bank'),'debit','12.00','credit','0'))
)::text,true);
select throws_ok($$select public.submit_journal_entry(current_setting('linkora_test.invalid_withdrawal')::uuid)$$,
 'Bank movement requires one classified cash/bank leg and one non-cash/bank counter-account leg in the correct direction','database prevents bank withdrawals with reversed accounting direction');

select set_config('linkora_test.payroll_employee',public.create_payroll_employee(current_setting('linkora_test.org_a')::uuid,'EMP-01','Synthetic Payroll Employee',current_setting('linkora_test.month_start')::date)::text,true);
select is((select employee_code from public.payroll_employees where id=current_setting('linkora_test.payroll_employee')::uuid),'EMP-01','authorized payroll member creates a synthetic employee');
select set_config('linkora_test.payroll_component',public.create_payroll_component(current_setting('linkora_test.org_a')::uuid,'BASE','Base salary','earning',current_setting('linkora_test.payroll_expense')::uuid)::text,true);
select is((select component_type from public.payroll_components where id=current_setting('linkora_test.payroll_component')::uuid),'earning','earning component maps to an unclassified expense account');
select set_config('linkora_test.payroll_run',public.create_payroll_run_draft(
 current_setting('linkora_test.org_a')::uuid,'PAY-TEST-001',current_setting('linkora_test.month_start')::date,current_setting('linkora_test.month_end')::date,current_setting('linkora_test.payroll_liability')::uuid,
 jsonb_build_array(jsonb_build_object('employee_id',current_setting('linkora_test.payroll_employee'),'component_id',current_setting('linkora_test.payroll_component'),'amount','1000.0000'))
)::text,true);
select is((select count(*)::integer from public.payroll_run_lines where run_id=current_setting('linkora_test.payroll_run')::uuid),1,'payroll draft snapshots the employee component line');
select set_config('linkora_test.payroll_journal',public.submit_payroll_run(current_setting('linkora_test.payroll_run')::uuid)::text,true);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.payroll_journal')::uuid),'submitted','payroll submission creates a normal maker-checker journal');
select is((select sum(debit)::numeric=sum(credit)::numeric from public.journal_lines where entry_id=current_setting('linkora_test.payroll_journal')::uuid),true,'payroll journal balances using exact NUMERIC amounts');
select throws_ok($$select public.approve_journal_entry(current_setting('linkora_test.payroll_journal')::uuid)$$,'Maker-checker: the creator cannot approve their own entry','payroll creator cannot approve the payroll journal');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.payroll_journal')::uuid);
select public.reject_journal_entry(current_setting('linkora_test.payroll_journal')::uuid,'Correct the synthetic payroll amount');
select is((select status from public.payroll_runs where id=current_setting('linkora_test.payroll_run')::uuid),'draft','rejected payroll journal returns its run to an editable draft');
select is((select rejection_reason from public.journal_entries where id=current_setting('linkora_test.payroll_journal')::uuid),'Correct the synthetic payroll amount','payroll rejection retains its required reason in the journal audit record');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select public.update_payroll_run_draft(current_setting('linkora_test.payroll_run')::uuid,jsonb_build_array(jsonb_build_object('employee_id',current_setting('linkora_test.payroll_employee'),'component_id',current_setting('linkora_test.payroll_component'),'amount','1200.0000')));
select is((select amount from public.payroll_run_lines where run_id=current_setting('linkora_test.payroll_run')::uuid),'1200.0000','payroll maker can correct rejected run snapshots transactionally');
select public.submit_payroll_run(current_setting('linkora_test.payroll_run')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.payroll_journal')::uuid);
select public.approve_journal_entry(current_setting('linkora_test.payroll_journal')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select public.post_journal_entry(current_setting('linkora_test.payroll_journal')::uuid);
select is((select status from public.payroll_runs where id=current_setting('linkora_test.payroll_run')::uuid),'posted','payroll run becomes posted only when its approved journal posts');
select is((select sum(credit::numeric) from public.journal_lines where entry_id=current_setting('linkora_test.payroll_journal')::uuid and account_id=current_setting('linkora_test.payroll_liability')::uuid),1200::numeric,'posted payroll credits exact net earnings to payroll payable');
select is(exists(select 1 from public.audit_logs where org_id=current_setting('linkora_test.org_a')::uuid and entity_id=current_setting('linkora_test.payroll_run')::uuid and entity_type='payroll_runs' and action='update'),true,'payroll status changes are captured in audit log');

select set_config('linkora_test.close_source',public.create_journal_entry_draft(
 current_setting('linkora_test.org_c')::uuid,current_date,'FY-SOURCE-001','Synthetic fiscal-year activity','USD',1,'general',
 jsonb_build_array(
  jsonb_build_object('account_id',current_setting('linkora_test.close_cash'),'debit','60.0000','credit','0'),
  jsonb_build_object('account_id',current_setting('linkora_test.close_expense'),'debit','40.0000','credit','0'),
  jsonb_build_object('account_id',current_setting('linkora_test.close_revenue'),'debit','0','credit','100.0000')
 )
)::text,true);
select public.submit_journal_entry(current_setting('linkora_test.close_source')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.close_source')::uuid);
select public.approve_journal_entry(current_setting('linkora_test.close_source')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select public.post_journal_entry(current_setting('linkora_test.close_source')::uuid);
select set_config('linkora_test.close_entry',public.create_fiscal_year_close_draft(current_setting('linkora_test.org_c')::uuid,
 (select id from public.accounting_periods where org_id=current_setting('linkora_test.org_c')::uuid and start_date=make_date(extract(year from current_date)::integer,12,1) and end_date=make_date(extract(year from current_date)::integer+1,1,1)-1),
 current_setting('linkora_test.close_equity')::uuid)::text,true);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.close_entry')::uuid),'submitted','year close creates a journal routed for maker-checker review');
select is((select sum(debit)::text from public.journal_lines where entry_id=current_setting('linkora_test.close_entry')::uuid),'100.0000','closing journal debits revenue by its exact ledger balance');
select is((select sum(credit)::text from public.journal_lines where entry_id=current_setting('linkora_test.close_entry')::uuid),'100.0000','closing journal credits expenses and net earnings using balanced NUMERIC amounts');
select is((select credit from public.journal_lines where entry_id=current_setting('linkora_test.close_entry')::uuid and account_id=current_setting('linkora_test.close_equity')::uuid),'60.0000','fiscal profit transfers to the selected retained earnings account');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.close_entry')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select throws_ok($$select public.approve_journal_entry(current_setting('linkora_test.close_entry')::uuid)$$,'Maker-checker: you cannot approve your own entry','year-close creator cannot approve their closing journal');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.approve_journal_entry(current_setting('linkora_test.close_entry')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select public.post_journal_entry(current_setting('linkora_test.close_entry')::uuid);
select is((select status from public.fiscal_year_closings where journal_entry_id=current_setting('linkora_test.close_entry')::uuid),'posted','fiscal close record updates only when its journal posts');
select is((select count(*)::integer from public.accounting_periods where org_id=current_setting('linkora_test.org_c')::uuid and start_date>=make_date(extract(year from current_date)::integer,1,1) and end_date<=make_date(extract(year from current_date)::integer+1,1,1)-1 and is_closed),12,'posting the year close locks every accounting period in that fiscal year');
select is((select amount from public.profit_and_loss_exact(current_setting('linkora_test.org_c')::uuid,make_date(extract(year from current_date)::integer,1,1),make_date(extract(year from current_date)::integer+1,1,1)-1) where type='revenue'),'100.0000','closed journal entries do not distort the reported fiscal-year revenue');
select is((select amount from public.profit_and_loss_exact(current_setting('linkora_test.org_c')::uuid,make_date(extract(year from current_date)::integer,1,1),make_date(extract(year from current_date)::integer+1,1,1)-1) where type='expense'),'40.0000','closed journal entries do not distort the reported fiscal-year expenses');
select is((select debit='0.0000' and credit='0.0000' from public.trial_balance_as_of_exact(current_setting('linkora_test.org_c')::uuid,make_date(extract(year from current_date)::integer+1,1,1)-1) where code='4000'),true,'year-end trial balance clears temporary revenue accounts');
select is((select coalesce(sum(balance::numeric) filter(where section='assets'),0)=coalesce(sum(balance::numeric) filter(where section in ('liabilities','equity')),0) from public.balance_sheet_exact(current_setting('linkora_test.org_c')::uuid,make_date(extract(year from current_date)::integer+1,1,1)-1)),true,'post-close balance sheet reconciles without double-counting current earnings');
select throws_ok($$update public.accounting_periods set is_closed=false where org_id=current_setting('linkora_test.org_c')::uuid and end_date=make_date(extract(year from current_date)::integer+1,1,1)-1$$,
 'Reverse the posted fiscal-year closing journal before reopening this period','database prevents reopening a year before its closing journal is reversed');
select set_config('linkora_test.closed_entry',public.create_journal_entry_draft(current_setting('linkora_test.org_c')::uuid,current_date,'FY-CLOSED-POST','Attempt to post into a closed fiscal year','USD',1,'general',
 jsonb_build_array(jsonb_build_object('account_id',current_setting('linkora_test.close_cash'),'debit','1.0000','credit','0'),jsonb_build_object('account_id',current_setting('linkora_test.close_revenue'),'debit','0','credit','1.0000')))::text,true);
select throws_ok($$select public.submit_journal_entry(current_setting('linkora_test.closed_entry')::uuid)$$,'Fiscal year is closed','database rejects submission into an earlier closed fiscal year period');
insert into public.accounting_periods(org_id,start_date,end_date,is_closed)
 values(current_setting('linkora_test.org_c')::uuid,make_date(extract(year from current_date)::integer+1,1,1),make_date(extract(year from current_date)::integer+1,1,31),false);
select set_config('linkora_test.close_reversal',public.reverse_journal_entry(current_setting('linkora_test.close_entry')::uuid,make_date(extract(year from current_date)::integer+1,1,1),'Synthetic fiscal close reversal')::text,true);
select public.submit_journal_entry(current_setting('linkora_test.close_reversal')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.close_reversal')::uuid);
select public.approve_journal_entry(current_setting('linkora_test.close_reversal')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select public.post_journal_entry(current_setting('linkora_test.close_reversal')::uuid);
select is((select status from public.fiscal_year_closings where journal_entry_id=current_setting('linkora_test.close_entry')::uuid),'reversed','posted reversal restores the fiscal close lifecycle state');
select is((select coalesce(sum(balance::numeric) filter(where section='assets'),0)=coalesce(sum(balance::numeric) filter(where section in ('liabilities','equity')),0) from public.balance_sheet_exact(current_setting('linkora_test.org_c')::uuid,make_date(extract(year from current_date)::integer+1,1,1)-1)),true,'balance sheet remains correct for the closed-year reporting date after a later reversal');
select is((select coalesce(sum(balance::numeric) filter(where section='assets'),0)=coalesce(sum(balance::numeric) filter(where section in ('liabilities','equity')),0) from public.balance_sheet_exact(current_setting('linkora_test.org_c')::uuid,make_date(extract(year from current_date)::integer+1,1,31))),true,'balance sheet remains correct after the closing journal reversal date');
select ok(exists(select 1 from public.audit_logs where org_id=current_setting('linkora_test.org_c')::uuid and entity_type='fiscal_year_closings' and entity_id=(select id from public.fiscal_year_closings where journal_entry_id=current_setting('linkora_test.close_entry')::uuid) and action='update'),'fiscal-year close and reversal lifecycle is audited');
update public.accounting_periods set is_closed=false where org_id=current_setting('linkora_test.org_c')::uuid and end_date=make_date(extract(year from current_date)::integer+1,1,1)-1;
select is((select is_closed from public.accounting_periods where org_id=current_setting('linkora_test.org_c')::uuid and end_date=make_date(extract(year from current_date)::integer+1,1,1)-1),false,'owner can reopen year-end after its closing journal is reversed');
select set_config('linkora_test.close_retry',public.create_fiscal_year_close_draft(current_setting('linkora_test.org_c')::uuid,
 (select id from public.accounting_periods where org_id=current_setting('linkora_test.org_c')::uuid and start_date=make_date(extract(year from current_date)::integer,12,1)),
 current_setting('linkora_test.close_equity')::uuid)::text,true);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.close_retry')::uuid),'submitted','a reversed fiscal year can be closed again after review');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select public.queue_journal_entry(current_setting('linkora_test.close_retry')::uuid);
select public.approve_journal_entry(current_setting('linkora_test.close_retry')::uuid);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select public.post_journal_entry(current_setting('linkora_test.close_retry')::uuid);
select is((select status from public.fiscal_year_closings where journal_entry_id=current_setting('linkora_test.close_retry')::uuid),'posted','reclosed fiscal year posts through the ordinary maker-checker process');

select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select set_config('linkora_test.closed_entry',public.create_journal_entry_draft(
 current_setting('linkora_test.org_a')::uuid,current_date,'TEST-CLOSED','Synthetic closed period entry','USD',1,'general',
 jsonb_build_array(
   jsonb_build_object('account_id',current_setting('linkora_test.cash'),'debit','5.00','credit','0'),
   jsonb_build_object('account_id',current_setting('linkora_test.revenue'),'debit','0','credit','5.00')
 )
)::text,true);
select is((select status::text from public.journal_entries where id=current_setting('linkora_test.closed_entry')::uuid),'draft','period test entry is an unposted draft');
update public.accounting_periods set is_closed=true where org_id=current_setting('linkora_test.org_a')::uuid and current_date between start_date and end_date;
select is((select is_closed from public.accounting_periods where org_id=current_setting('linkora_test.org_a')::uuid and current_date between start_date and end_date),true,'owner can close the current accounting period');
select throws_ok($$select public.submit_journal_entry(current_setting('linkora_test.closed_entry')::uuid)$$,
 'Accounting period is closed','database rejects submission into a closed accounting period');
select public.add_organization_member(current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.outsider')::uuid,'viewer');
select is((select role::text from public.organization_members where org_id=current_setting('linkora_test.org_a')::uuid and user_id=current_setting('linkora_test.outsider')::uuid),'viewer','owner adds an existing Auth user with a read-only role');
select public.set_organization_member_role(current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.outsider')::uuid,'approver');
select is((select role::text from public.organization_members where org_id=current_setting('linkora_test.org_a')::uuid and user_id=current_setting('linkora_test.outsider')::uuid),'approver','owner can change an organization role');
select ok(exists(select 1 from public.audit_logs where org_id=current_setting('linkora_test.org_a')::uuid and user_id=current_setting('linkora_test.maker')::uuid and entity_type='organization_members' and entity_id=current_setting('linkora_test.outsider')::uuid and action='update'),'role changes are recorded in the audit trail');
select public.remove_organization_member(current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.outsider')::uuid);
select is((select count(*)::integer from public.organization_members where org_id=current_setting('linkora_test.org_a')::uuid and user_id=current_setting('linkora_test.outsider')::uuid),0,'owner can remove an existing member');
select throws_ok($$select public.set_organization_member_role(current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.maker')::uuid,'finance_manager')$$,
 'An organization must retain at least one owner','database prevents demotion of the last owner');
select public.set_organization_member_role(current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.checker')::uuid,'administrator');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.checker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.checker'),'role','authenticated','aud','authenticated')::text,true);
select throws_ok($$select public.add_organization_member(current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.outsider')::uuid,'owner')$$,
 'Only the owner can assign owner or administrator roles','administrator cannot grant owner membership');
select throws_ok($$select public.set_organization_member_role(current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.maker')::uuid,'finance_manager')$$,
 'Only the owner can change owner or administrator roles','administrator cannot change owner role');
select throws_ok($$select public.remove_organization_member(current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.maker')::uuid)$$,
 'Only the owner can remove an owner or administrator','administrator cannot remove owner membership');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select set_config('request.jwt.claim.sub',current_setting('linkora_test.outsider'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.outsider'),'role','authenticated','aud','authenticated')::text,true);
select throws_ok($$select * from public.statement_of_changes_in_equity_exact(current_setting('linkora_test.org_a')::uuid,current_date,current_date)$$,
 'Not authorized to view this organization','equity statement RPC refuses another organization');
select set_config('request.jwt.claim.sub',current_setting('linkora_test.maker'),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('linkora_test.maker'),'role','authenticated','aud','authenticated')::text,true);
select is((
  select coalesce(sum(closing_balance::numeric),0)=(
    select coalesce(sum(balance::numeric),0) from public.balance_sheet_exact(current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.month_end')::date) where section='equity'
  ) from public.statement_of_changes_in_equity_exact(current_setting('linkora_test.org_a')::uuid,current_setting('linkora_test.month_start')::date,current_setting('linkora_test.month_end')::date)
),true,'statement of changes in equity reconciles its closing balance to the balance sheet');

select * from finish();
rollback;
