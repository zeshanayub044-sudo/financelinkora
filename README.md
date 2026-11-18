# Linkora Finance

Linkora Finance is a branded Next.js 16 and TypeScript financial workspace. It preserves the original database foundation and adds incremental database hardening and accounting workflows.

## Supabase target

The selected development and testing target is the existing Free project `jztejhppiepczvqiebik` in the Linkora Finance organization `roszvxdeseeatthlkhwm`. It is hosted in Seoul (`ap-northeast-2`), not Mumbai. A read-only catalog audit found no application tables, custom schemas, Auth users, Storage buckets, or Storage objects. No migration has been applied from this workspace, and no frontend secrets are configured here.

The project is still on the Free plan. Free includes 500 MB database storage, 5 GB egress, 1 GB file storage, and 50,000 monthly active users; projects may pause after a week of low activity. There are no automatic database backups or point-in-time recovery on Free. Do not use this project for production accounting records until backup, recovery, RLS, and real-accounting tests have passed and the availability limitations have been accepted.

## Included

- Responsive Linkora application shell, brand assets, light/dark theme, tables, search, and role-aware navigation.
- Supabase Auth login, registration, password recovery, reset, server-rendered cookie sessions, and protected workspace routes.
- Organization setup and starter chart of accounts through the existing setup RPC.
- Journal line amounts stay as decimal strings in browser validation and RPC payloads; debit/credit balancing and currency formatting use integer decimal units for up to four places.
- Exact-decimal read models return PostgreSQL numeric report and ledger values as text to avoid JavaScript number conversion in accounting tables and KPIs. Chart plot values are converted to numbers only for visualization.
- Dashboard reads posted ledger data and returns empty states when there are no posted entries.
- Chart of Accounts, journal creation/detail, staged approval controls, ledger, trial balance, accounting periods, and audit views.
- Additive hardening migrations for maker-checker workflow, database-enforced posting and reversals, audit capture, period validation, cross-organization references, and accounting reports.
- Explicit development states for modules without supporting database tables or procedures.

## Run locally

Requirements: Node.js 20.9+ and pnpm 10+.

```powershell
pnpm install
Copy-Item .env.example .env.local
```

Set the selected project's URL and publishable key in `.env.local`:

```env
NEXT_PUBLIC_SUPABASE_URL=https://jztejhppiepczvqiebik.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Then run `pnpm dev` and open `http://localhost:3000`. Publishable keys are intended for browser use; never add a service-role key or database password to `NEXT_PUBLIC_*` variables or commit `.env.local`.

## Apply database migrations

The original `supabase/migrations/0001_foundation_and_ledger.sql` is preserved. Apply all files in order using the Supabase CLI so the database migration history remains synchronized:

```powershell
pnpm dlx supabase@latest login
pnpm dlx supabase@latest link --project-ref jztejhppiepczvqiebik
pnpm dlx supabase@latest migration list --linked
pnpm dlx supabase@latest db push --linked --dry-run
pnpm dlx supabase@latest db push --linked
```

Review the dry-run output carefully. The project must still be the selected Linkora Finance Free project. `db push` applies the historical foundation first, then `20261117000100_extend_workflow_roles.sql`, `20261117000200_accounting_workflow_and_security.sql`, `20261117000300_validate_functional_currency_balance.sql`, `20261117000400_editable_journal_drafts.sql`, `20261117000500_validate_transaction_kinds.sql`, `20261118000100_guard_opening_balances.sql`, `20261118000200_exact_decimal_read_models.sql`, `20261118000300_audit_reader_roles.sql`, `20261118000400_guard_posted_account_identity.sql`, `20261118000500_budget_planning.sql`, `20261118000600_explicit_account_reporting_class.sql`, `20261118000700_strict_bank_transfer_integrity.sql`, `20261118000800_bank_statement_reconciliation.sql`, `20261118000900_statement_balance_reconciliation.sql`, `20261118001000_receivables_payables.sql`, `20261118001100_cash_flow_reporting.sql`, `20261118001200_fixed_assets.sql`, `20261118001300_statement_of_changes_in_equity.sql`, `20261118001400_manual_transaction_currency.sql`, `20261118001500_departments_projects.sql`, `20261118001600_financial_ratios.sql`, `20261118001700_configurable_tax.sql`, `20261118001800_payroll_workflow.sql`, `20261118001900_bank_deposit_withdrawal.sql`, `20261118002000_private_receipt_attachments.sql`, and `20261118002100_recurring_income_expense.sql`. Migrations 015–021 add tenant-scoped dimensions, posted-ledger financial ratios, configurable document tax, payroll records with maker-checker journals, validated bank deposits and withdrawals, private receipt storage, and user-triggered recurring income/expense journal drafts. The enum migration is separate because PostgreSQL requires new enum labels to commit before later migrations use them. Do not run the foundation migration alone as an exposed application; the hardening migrations are required before inviting users.

The current workspace's Supabase MCP connection does not have permission for this project, and the Supabase CLI is not installed here. Therefore live migrations and database-level tests have **not** been run from this workspace.

## Authentication setup

In Supabase Auth, enable the providers you intend to use and configure the site URL and allowed redirects:

- Local: `http://localhost:3000/auth/callback`
- Hosted: `https://YOUR_DOMAIN/auth/callback`

The app does not create local or hardcoded sessions. Create an Auth account through `/signup`, then use organization setup to create an organization and starter ledger. Invite another authorized member before testing maker-checker approval.

## Tests

Local tests do not need a live project:

```powershell
pnpm typecheck
pnpm test
pnpm lint
pnpm build
```

`src/lib/supabase/integration.test.ts` is a read-only live smoke-test preparation. It runs only when the URL exactly matches the approved Linkora project and `SUPABASE_TEST_ORG_ID`, a publishable key, and dedicated test-account email/password are provided. It checks membership, exact-decimal RPCs, and a nonexistent entry lookup; it does not provision financial records. Hosted migration execution, RLS, journal posting/reversal, period locks, and report reconciliation still need live verification after local database tests pass.

Database security and workflow tests (140 pgTAP assertions) are in `supabase/tests/accounting_security.test.sql`. They use synthetic users, organizations, accounts, journals, reversals, budgets, payroll, statement imports, fixed assets, and membership changes in one transaction and roll back. Run them only against the local Supabase stack:

```powershell
pnpm dlx supabase@latest start
pnpm dlx supabase@latest test db
pnpm dlx supabase@latest stop
```

The test command defaults to the local database. Do not use its remote/linked options for this suite. The local Supabase CLI/database runtime is unavailable in this workspace, so these database tests have not yet been executed. The 140 pgTAP assertions cover RLS organization isolation including statement data, protected journal creation, maker-checker submission and approval, posting, exact-trial-balance and cash totals, audit capture, reversals, budget approval/variance, closed-period submission rejection, single-transfer line integrity, account cash-flow classification, internal transfers' separation from income, expenses, and account balances, statement import, exact matching, balance reconciliation differences, audit events, invoice partial payment and reversal restrictions, receivables aging, cash-flow reconciliation, a protected fixed-asset acquisition, and a maker-checker straight-line depreciation journal, including equity-statement closing reconciliation to the balance sheet, exact manual exchange-rate storage with functional-currency rounding, tenant-scoped department/project creation and audit, posted department/project profitability, seven posted-ledger financial ratio measures, tax code policies and calculations, deposit and withdrawal workflow/direction constraints, receipt bucket privacy/RLS/metadata grants, recurring template scheduling, journal link and tenant denial, internal-transfer misclassification rejection, and payroll employee/component creation, exact balanced payroll journal generation, creator approval denial, rejection reason audit, editable rejected-run correction, re-submission, posting of exact net payables, post-gated run status, and payroll audit logging.

## Backup and recovery on Free

Supabase Free does not provide automatic database backups, downloadable platform backups, or PITR. Before applying schema changes and at least weekly, export the database with the Supabase CLI, encrypt the backup, and store it outside this repository and outside the Supabase project:

```powershell
pnpm dlx supabase@latest db dump --linked --file .\linkora-backup.sql
```

Keep access tightly restricted and remove local copies after transferring them to approved encrypted storage. Export the private `linkora-finance-receipts` bucket separately at the same cadence using the Storage dashboard or authenticated Storage API; preserve each object path. To recover, restore the database dump into a separate disposable local PostgreSQL/Supabase instance first, validate schema and accounting totals there, then reapply migrations and restore bucket objects to the matching paths before reviewed access is restored. A database dump does not contain Storage objects. Neither the database nor object restore procedure has been exercised, so this is a manual procedure, not a disaster-recovery guarantee.

## Module status

| Module | Current state |
| --- | --- |
| Auth, organization setup, membership, chart of accounts | Supabase Auth and owner/admin membership and role controls implemented; adds existing Auth UUIDs (does not invite/create users); incremental identity guard protects posted account classification; live configuration not verified |
| Journal draft, edit, submit, review queue, approve, reject, post, reverse | Frontend and additive SQL implemented; drafts can be saved unbalanced, while submit/approve/post require balance; migrations and live workflow tests pending |
| Ledger, trial balance, P&L, balance sheet, statement of changes in equity, dashboard summaries | Equity statement reports opening balance, account movement, and cumulative unclosed earnings; a synthetic SQL assertion reconciles closing equity to the balance sheet. Migration and live verification pending |
| Accounting periods and audit log | Interfaces and additive integrity/audit SQL prepared; live RLS tests pending |
| Income and paid expenses | Journal-backed drafts use the approval/post workflow; migration 005 constrains account directions. Not live verified. Receipt files can be attached from income/expense journal detail after migration 020. Migration 021 adds monthly, quarterly, and annual schedule templates that generate user-triggered, unposted journal drafts with open-period, account, and tenant checks. No automatic scheduler is used. Migrations 020–021 require SQL execution and live verification. |
| Budgets | Monthly account plans, draft editing, maker-checker approval, and variance against posted ledger activity implemented in migration 20261118000500; not deployed or live tested |
| Dashboard liquidity and working capital | Cash, bank, receivable, and payable are assigned by explicit audited account classifications in migration 20261118000600; starter chart codes are backfilled; custom accounts require classification; not deployed or live tested |
| Banking | Internal transfers use approved journal workflows and are constrained to cash/bank accounts; CSV bank statement import and exact same-account matching to posted ledger lines are implemented through additive migrations 008–009. New imports capture statement dates and opening/closing balances, with exact NUMERIC reconciliation against functional-currency ledger balances and audited matching. Not locally SQL-tested or hosted verified. Deposits and withdrawals use distinct journal kinds and database-enforced classified cash/bank legs (migration 019), but remain unverified until local SQL tests run |
| Opening balances | Owner/finance manager UI selection and migration `20261118000100_guard_opening_balances.sql` restricts opening entries to balance sheet accounts; migrations and live workflow are not verified |
| Customers, suppliers, invoices, bills, payments, and aging | Incremental migration 010 adds tenant-scoped records, accrual journal creation, maker-checker submission/posting, payment reservation, exact outstanding balances, as-of aging buckets, and reversal-based voiding for unpaid invoices/bills. Customer, supplier, invoice, bill, and payment screens use these RPCs. Migration and pgTAP flows are not executed locally or hosted. Delivery, party histories, payment resubmission UI, and cash-basis posting remain incomplete. Receipt attachment is available on income/expense journal detail after migration 020. |
| Cash flow statement | Direct cash-flow report from posted counterpart journal lines, with auditable per-account operating/investing/financing classification, an explicit unclassified bucket, opening/closing cash, ledger movement reconciliation, and CSV export implemented in migration 011. It is not locally SQL-tested or hosted verified; reviewers must confirm account classifications and policy before using it as a formal IFRS statement. |
| Fixed assets and depreciation | Incremental migration 012 adds an audited register linked to posted base-currency acquisition journals, an accumulated-depreciation contra-asset class, exact straight-line monthly schedules, and depreciation journal drafts routed through maker-checker posting. It assumes a full month of depreciation from the in-service month and requires periods to be posted in sequence. Migration and pgTAP flows are not locally or hosted verified. Disposal, impairment, alternative methods, partial-month conventions, and FX assets remain incomplete. |
| Changes in equity | Migration 013 reports opening balances, period movement by equity account, and cumulative unclosed earnings. Contribution/distribution labels are not inferred; migration and query are not SQL-tested. |
| Manual transaction currency | General journal entries accept a three-letter transaction currency and manually entered NUMERIC exchange rate. Functional-currency amounts are rounded to four places and the rate is audit logged with the entry; no rate feed, revaluation, or realized/unrealized FX accounting is implemented. SQL and hosted tests pending. |
| Departments and projects | Implemented in migration 015 with tenant-scoped records, audit logging, active-dimension enforcement, per-journal-line allocation, and posted-activity reports. Migration and SQL suite have not run locally or against the hosted project. |
| Financial ratios | Migration 016 derives debt-to-equity, liabilities-to-assets, return on assets, return on equity, net profit margin, expense-to-income, and classified cash-to-payables from exact posted-ledger summaries; denominator-zero values are N/A. It requires explicit account classifications and has not run through local SQL tests or hosted verification. |
| Tax management | Migration 017 adds organization-scoped, audited, immutable tax codes with manual rates/effective dates, tax-exclusive invoice and bill calculation, four-place NUMERIC rounding, output liability and recoverable input-tax postings, gross receivables/payables, and a posted/reversal-aware activity schedule. No jurisdiction or rate is assumed. Migration and SQL suite remain unrun. |
| Receipt attachments | Migration 020 creates a private bounded bucket, tenant-linked metadata with audit triggers, role-scoped object read/upload policies, short-lived signed downloads, and cleanup limited to unregistered orphan uploads. Only income/expense journal entries expose this panel. Bucket collision stops migration rather than reusing existing storage. Not deployed or SQL-tested. |
| Recurring income and expenses | Migration 021 stores audited tenant-scoped templates and immutable occurrences; authorized users explicitly generate scheduled journal drafts, with due-date cadence, open-period, account, and maker checks. No background job auto-posts transactions. Not deployed or SQL-tested. |
| Payroll | Implemented locally: confidential employee and component records, monthly payroll drafts, manual earning/deduction entry, rejection correction, and journal submission through maker-checker posting. Jurisdiction-specific payroll calculations and payslips are not implemented. Migration 018 and payroll pgTAP cases require local/live database execution before use. |

New bank statement imports require a date range, opening balance, closing balance, and signed transaction rows in the organization's base currency. The report compares the statement opening/closing balances with posted functional-currency ledger balances and shows statement-activity and unmatched-activity differences. Imports created before migration 009 have no supplied balances; those remain visible as legacy imports without a full balance reconciliation. No opening or closing values are inferred for them.

The reports use posted and reversed journal entries; Trial Balance now reports cumulative balances as of a selected date. Opening balance entries are constrained to balance sheet accounts and owner/finance manager creation, but that migration has not been deployed or live-tested. Cash-flow account classifications and reconciliation are implemented in migration 011 but remain untested against PostgreSQL. Period closing transfers and foreign-currency revaluation are not supported; do not represent these reports as IFRS-complete financial statements.

## Free-plan region and limitations

Pakistan users will generally see more network latency from Seoul than from a nearer South Asian region such as Mumbai. Region cannot be changed in place; moving would require creating and validating a separate project and migrating data. Keep the current project rather than taking a data-loss or additional-cost risk solely to change region. Free projects can pause after inactivity, have limited storage/egress, and do not include automatic backups or an uptime SLA.

## Deployment

The application has no Vercel or custom-domain configuration and has not been deployed. After live database verification, configure the same publishable Supabase URL/key as deployment environment variables, set the production Auth callback URL, deploy from the existing GitHub repository, then verify sign-in, protected routes, responsive layouts, and the database workflows. Confirm the hosting provider's current free-tier limits and possible costs before enabling billing or paid features.
