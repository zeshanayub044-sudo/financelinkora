# Linkora Finance

Linkora Finance is a branded Next.js 16 and TypeScript financial workspace. It preserves the original database foundation and adds incremental database hardening and accounting workflows.

## Supabase target

The selected development and testing target is the existing project `jztejhppiepczvqiebik` in the Linkora Finance organization `roszvxdeseeatthlkhwm`, based on the project details supplied by the owner. The supplied details say Free plan, Nano compute, and Seoul (`ap-northeast-2`), not Mumbai. **This workspace has not independently verified the organization, plan, region, database contents, Auth users, Storage, functions, or project activity.** There is no `.env.local`, Supabase CLI, or connected Supabase tool configured here, so no hosted catalog audit has been performed from this workspace. No migration has been applied from this workspace.

The project's current plan has not been independently checked here. Supabase lists the Free plan at $0/month with 500 MB database size, 5 GB uncached egress plus 5 GB cached egress, 1 GB file storage, and 50,000 monthly active users; Free projects may pause after one week of low activity and do not include automatic backups or point-in-time recovery. The current limits also include a 50 MB maximum upload, one-day platform log retention, 24-hour Auth audit log retention, and two active Free projects across organizations where the account is an owner or administrator. These quotas and terms can change; check the live [Supabase pricing page](https://supabase.com/pricing) and [billing documentation](https://supabase.com/docs/guides/platform/billing-on-supabase) before relying on them. Do not use this project for production accounting records until project contents, backup/recovery, RLS, and accounting workflows have been inspected and tested against the actual database.

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

The application validates this URL before creating a Supabase client. Hosted connections are limited to the selected Linkora Finance project; local development may use the standard `http://127.0.0.1:54321` or `http://localhost:54321` Supabase API. Other hosted project references fail closed to avoid accidentally connecting this app to an unrelated Supabase project.

Then run `pnpm dev` and open `http://localhost:3000`. Publishable keys are intended for browser use; never add a service-role key or database password to `NEXT_PUBLIC_*` variables or commit `.env.local`.

## Apply database migrations

The original `supabase/migrations/0001_foundation_and_ledger.sql` is preserved. Apply all files in order using the Supabase CLI so the database migration history remains synchronized:

```powershell
pnpm dlx supabase@latest login
pnpm dlx supabase@latest migration list --remote=jztejhppiepczvqiebik
pnpm dlx supabase@latest db push --dry-run --remote=jztejhppiepczvqiebik
pnpm dlx supabase@latest db push --remote=jztejhppiepczvqiebik
```

Before applying anything, perform a read-only catalog, data, Auth, Storage, and existing-application inspection and establish that this project is safe to repurpose. A migration dry run shows pending migration files; it does not prove that existing project data or services are safe to overwrite. Stop if contents are present or cannot be established. Confirm the dry-run `Target:` line identifies exactly `jztejhppiepczvqiebik`; the final command applies changes only after CLI confirmation. Decline if the target or listed changes are unexpected. See the [current CLI remote-target behavior](https://supabase.com/docs/reference/cli/supabase-db-push). `db push` applies the historical foundation first, then `20261117000100_extend_workflow_roles.sql`, `20261117000200_accounting_workflow_and_security.sql`, `20261117000300_validate_functional_currency_balance.sql`, `20261117000400_editable_journal_drafts.sql`, `20261117000500_validate_transaction_kinds.sql`, `20261118000100_guard_opening_balances.sql`, `20261118000200_exact_decimal_read_models.sql`, `20261118000300_audit_reader_roles.sql`, `20261118000400_guard_posted_account_identity.sql`, `20261118000500_budget_planning.sql`, `20261118000600_explicit_account_reporting_class.sql`, `20261118000700_strict_bank_transfer_integrity.sql`, `20261118000800_bank_statement_reconciliation.sql`, `20261118000900_statement_balance_reconciliation.sql`, `20261118001000_receivables_payables.sql`, `20261118001100_cash_flow_reporting.sql`, `20261118001200_fixed_assets.sql`, `20261118001300_statement_of_changes_in_equity.sql`, `20261118001400_manual_transaction_currency.sql`, `20261118001500_departments_projects.sql`, `20261118001600_financial_ratios.sql`, `20261118001700_configurable_tax.sql`, `20261118001800_payroll_workflow.sql`, `20261118001900_bank_deposit_withdrawal.sql`, `20261118002000_private_receipt_attachments.sql`, `20261118002100_recurring_income_expense.sql`, `20261118002200_correct_rejected_payments.sql`, `20261118002300_fixed_asset_disposals.sql`, and `20261118002400_fiscal_year_close_workflow.sql`. Migrations 015–024 add tenant-scoped dimensions, posted-ledger financial ratios, configurable document tax, payroll records with maker-checker journals, validated bank deposits and withdrawals, private receipt storage, user-triggered recurring income/expense journal drafts, atomic correction/resubmission for rejected invoice and bill payments, approval-gated fixed-asset disposal accounting, and fiscal-year close journals with immutable posting and period locking. The enum migration is separate because PostgreSQL requires new enum labels to commit before later migrations use them. Do not run the foundation migration alone as an exposed application; the hardening migrations are required before inviting users.

The Supabase CLI is not installed in this workspace, and there are no project credentials configured here. Therefore project metadata inspection, live migrations, and database-level tests have **not** been run from this workspace. Do not link the CLI or apply migrations until an authorized operator has confirmed the target project and reviewed the migration dry run.

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

The GitHub Actions workflow at `.github/workflows/ci.yml` runs the application checks and starts an isolated local Supabase stack to rebuild the database from migrations and run pgTAP. It uses no Supabase project credentials and never targets the hosted project. Its database job is the repeatable CI path for SQL verification; a green local CI result still does not replace the separately required hosted configuration and access-isolation audit.

Database security and workflow tests (200 pgTAP assertions) are in `supabase/tests/accounting_security.test.sql`. They use synthetic users, organizations, accounts, journals, reversals, budgets, payroll, statement imports, fixed assets, and membership changes in one transaction and roll back. Run them only against the local Supabase stack:

```powershell
pnpm dlx supabase@latest start
pnpm dlx supabase@latest test db --local
pnpm dlx supabase@latest stop
```

The test command is explicitly pinned to the local database. Never add `--remote`, `--linked`, `--db-url`, or `--yes` to this suite. Supabase CLI versions print the resolved target; confirm it identifies the local stack before proceeding. The local Supabase CLI/database runtime is unavailable in this workspace, so these database tests have not yet been executed. The 200 pgTAP assertions cover organization setup, owner assignment, starter accounts, administrator restrictions on assigning/removing privileged roles, audit-log immutability and tenant isolation, RLS organization isolation including statement data, fixed assets, and fiscal close records; journal maker-checker submission, approval, posting, reversals, exact trial balance and cash totals, audit capture; budget approval and variance; closed-period and closed-fiscal-year posting rejection; bank transfer, statement import/matching/reconciliation; invoices, partial payments, reversals, and aging; cash-flow reconciliation; fixed-asset acquisition, sequential depreciation, disposal gain/loss, approval, audit and reversal restoration; fiscal-year close NUMERIC balancing, retained earnings transfer, temporary-account clearing, full-year locking, closed-year report reconciliation, audited reversal, reopening and re-close; equity statement reconciliation; manual exchange-rate storage; department/project authorization and profitability; financial ratios; tax; bank deposits and withdrawals; receipt bucket privacy; recurring template scheduling; rejected payment correction; and payroll generation, approval, correction, posting, and audit logging. All database cases require local execution before live use.

## Backup and recovery on Free

Supabase Free does not provide automatic database backups, downloadable platform backups, or PITR. Before applying schema changes and at least weekly, use the Supabase CLI with Docker to create separate role, schema, and data dumps. A plain `db dump` is schema-only; it is not a data backup. Run from an encrypted workstation and write to a private backup directory outside this repository:

```powershell
New-Item -ItemType Directory -Force $env:USERPROFILE\Documents\Linkora-Backup
pnpm dlx supabase@latest db dump --role-only --file $env:USERPROFILE\Documents\Linkora-Backup\roles.sql --remote=jztejhppiepczvqiebik
pnpm dlx supabase@latest db dump --file $env:USERPROFILE\Documents\Linkora-Backup\schema.sql --remote=jztejhppiepczvqiebik
pnpm dlx supabase@latest db dump --data-only --use-copy -x storage.buckets_vectors -x storage.vector_indexes --file $env:USERPROFILE\Documents\Linkora-Backup\data.sql --remote=jztejhppiepczvqiebik
```

The CLI dump excludes Supabase-managed `auth` and `storage` schemas and extension schemas. It does not back up Auth users or Storage bucket metadata/objects; maintain a separate tested user re-invitation plan. Export private receipt objects separately at the same cadence through an authorized Storage workflow, preserving exact object paths. Supabase database dumps never include Storage file contents. Encrypt all dump files before copying them off-device, restrict access, and remove temporary plaintext files.

To recover, use Supabase's documented logical restore procedure in a separate disposable project or local Supabase instance; never restore over a live project until its contents and target are confirmed and a separate approval has been given. Validate migration state, RLS, Auth access, receipt paths, trial balance, and financial statement reconciliation in the isolated restore before considering service recovery. Neither this backup nor restore procedure has been exercised, so this is a manual process, not a tested disaster-recovery guarantee. See the official [CLI backup and restore guide](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore) and [backup availability documentation](https://supabase.com/docs/guides/platform/backups) for current requirements and exclusions.

## Module status

| Module | Current state |
| --- | --- |
| Auth, organization setup, membership, chart of accounts | Supabase Auth and owner/admin membership and role controls implemented; adds existing Auth UUIDs (does not invite/create users); incremental identity guard protects posted account classification; live configuration not verified |
| Journal draft, edit, submit, review queue, approve, reject, post, reverse | Frontend and additive SQL implemented; drafts can be saved unbalanced, while submit/approve/post require balance; migrations and live workflow tests pending |
| Ledger, trial balance, P&L, balance sheet, statement of changes in equity, dashboard summaries | Equity statement reports opening balance, account movement, and cumulative unclosed earnings; a synthetic SQL assertion reconciles closing equity to the balance sheet. Migration and live verification pending |
| Accounting periods and audit log | Monthly period controls are implemented. Migration 024 adds maker-checker fiscal-year close journals, exact cumulative P&L balance sweeps into retained earnings, period-wide locks after posting, reversal-aware historical reporting, audited close status, and re-close after an approved reversal. The synthetic SQL suite covers these paths but remains unexecuted locally and hosted. |
| Income and paid expenses | Journal-backed drafts use the approval/post workflow; migration 005 constrains account directions. The history screens filter organization-scoped journal entries by date range and revenue/expense account category, display linked categories, and show exact posted ledger amounts; drafts are labeled not posted. Not live verified. Receipt files can be attached from income/expense journal detail after migration 020. Migration 021 adds monthly, quarterly, and annual schedule templates that generate user-triggered, unposted journal drafts with open-period, account, and tenant checks. No automatic scheduler is used. Migrations 020–021 require SQL execution and live verification. |
| Budgets | Monthly account plans, draft editing, maker-checker approval, and variance against posted ledger activity implemented in migration 20261118000500; not deployed or live tested |
| Dashboard liquidity and working capital | Cash, bank, receivable, and payable are assigned by explicit audited account classifications in migration 20261118000600; starter chart codes are backfilled; custom accounts require classification; not deployed or live tested |
| Banking | Internal transfers use approved journal workflows and are constrained to cash/bank accounts; CSV bank statement import and exact same-account matching to posted ledger lines are implemented through additive migrations 008–009. New imports capture statement dates and opening/closing balances, with exact NUMERIC reconciliation against functional-currency ledger balances and audited matching. Not locally SQL-tested or hosted verified. Deposits and withdrawals use distinct journal kinds and database-enforced classified cash/bank legs (migration 019), but remain unverified until local SQL tests run |
| Opening balances | Owner/finance manager UI selection and migration `20261118000100_guard_opening_balances.sql` restricts opening entries to balance sheet accounts; migrations and live workflow are not verified |
| Customers, suppliers, invoices, bills, payments, and aging | Incremental migration 010 adds tenant-scoped records, accrual journal creation, maker-checker submission/posting, payment reservation, exact outstanding balances, as-of aging buckets, and reversal-based voiding for unpaid invoices/bills. Customer and supplier detail pages show document history, issued-only paid/outstanding totals, each payment’s journal status, and journal links. Invoice and bill detail pages show tax-aware line items, posted journal status, payments, and ledger links. Migration and pgTAP flows are not executed locally or hosted. Delivery and cash-basis posting remain incomplete. Rejected payment correction and resubmission are implemented in migration 022. Receipt attachment is available on income/expense journal detail after migration 020. |
| Cash flow statement | Direct cash-flow report from posted counterpart journal lines, with auditable per-account operating/investing/financing classification, an explicit unclassified bucket, opening/closing cash, ledger movement reconciliation, and CSV export implemented in migration 011. It is not locally SQL-tested or hosted verified; reviewers must confirm account classifications and policy before using it as a formal IFRS statement. |
| Fixed assets and depreciation | Migration 012 adds an audited register linked to posted base-currency acquisition journals and exact straight-line monthly schedules. Migration 023 adds a database-validated disposal draft: proceeds, asset cost, posted accumulated depreciation, and gain/loss are balanced using NUMERIC and sent through maker-checker approval; the register changes only when posted, and a posted reversal reopens the asset with traceable history. Disposal uses month-end dates and requires depreciation through that month to be resolved. Local SQL/RLS and live tests remain pending. Impairment, alternatives to straight-line, partial-month conventions, and FX assets remain incomplete. |
| Changes in equity | Migration 013 reports opening balances, period movement by equity account, and cumulative unclosed earnings. Contribution/distribution labels are not inferred; migration and query are not SQL-tested. |
| Manual transaction currency | General journal entries accept a three-letter transaction currency and manually entered NUMERIC exchange rate. Functional-currency amounts are rounded to four places and the rate is audit logged with the entry; no rate feed, revaluation, or realized/unrealized FX accounting is implemented. SQL and hosted tests pending. |
| Departments and projects | Implemented in migration 015 with tenant-scoped records, audit logging, active-dimension enforcement, per-journal-line allocation, and posted-activity reports. Migration and SQL suite have not run locally or against the hosted project. |
| Financial ratios | Migration 016 derives debt-to-equity, liabilities-to-assets, return on assets, return on equity, net profit margin, expense-to-income, and classified cash-to-payables from exact posted-ledger summaries; denominator-zero values are N/A. It requires explicit account classifications and has not run through local SQL tests or hosted verification. |
| Tax management | Migration 017 adds organization-scoped, audited, immutable tax codes with manual rates/effective dates, tax-exclusive invoice and bill calculation, four-place NUMERIC rounding, output liability and recoverable input-tax postings, gross receivables/payables, and a posted/reversal-aware activity schedule. No jurisdiction or rate is assumed. Migration and SQL suite remain unrun. |
| Receipt attachments | Migration 020 creates a private bounded bucket, tenant-linked metadata with audit triggers, role-scoped object read/upload policies, short-lived signed downloads, and cleanup limited to unregistered orphan uploads. Only income/expense journal entries expose this panel. Bucket collision stops migration rather than reusing existing storage. Not deployed or SQL-tested. |
| Recurring income and expenses | Migration 021 stores audited tenant-scoped templates and immutable occurrences; authorized users explicitly generate scheduled journal drafts, with due-date cadence, open-period, account, and maker checks. No background job auto-posts transactions. Not deployed or SQL-tested. |
| Payroll | Implemented locally: confidential employee and component records, monthly payroll drafts, manual earning/deduction entry, rejection correction, and journal submission through maker-checker posting. Jurisdiction-specific payroll calculations and payslips are not implemented. Migration 018 and payroll pgTAP cases require local/live database execution before use. |

New bank statement imports require a date range, opening balance, closing balance, and signed transaction rows in the organization's base currency. The report compares the statement opening/closing balances with posted functional-currency ledger balances and shows statement-activity and unmatched-activity differences. Imports created before migration 009 have no supplied balances; those remain visible as legacy imports without a full balance reconciliation. No opening or closing values are inferred for them.

The reports use posted and reversed journal entries; Trial Balance now reports cumulative balances as of a selected date. Opening balance entries are constrained to balance sheet accounts and owner/finance manager creation, but that migration has not been deployed or live-tested. Cash-flow account classifications and reconciliation are implemented in migration 011 but remain untested against PostgreSQL. Migration 024 adds approved fiscal-year closing transfers and prevents backdated posting throughout a closed year; this SQL has not been run against PostgreSQL or the hosted project. Foreign-currency revaluation is not implemented; do not represent these reports as IFRS-complete financial statements.

CSV exports are offered alongside native Excel-compatible `.xlsx` exports for report views with an export action. XLSX cells are stored as text to preserve full PostgreSQL decimal precision and prevent spreadsheet formula execution. `Print / Save PDF` opens the browser print dialog; choose the browser's Save as PDF destination. Print styling hides application navigation and report controls and prints all filtered rows, including rows beyond the on-screen page. This uses browser-provided PDF output and does not create a server-side PDF file.

## Free-plan region and limitations

Pakistan users will generally see more network latency from Seoul than from a nearer South Asian region such as Mumbai. Region cannot be changed in place; moving would require creating and validating a separate project and migrating data. Keep the current project rather than taking a data-loss or additional-cost risk solely to change region. Free projects can pause after inactivity, have limited storage/egress, and do not include automatic backups or an uptime SLA.

## Optional AI finance assistant (not implemented)

No AI model, external AI API, or assistant UI is enabled. A future assistant should run only on an explicitly requested, server-side, read-only path that uses the signed-in user's Supabase session and organization membership. It should read authorized, posted-ledger summaries through existing report functions, minimize the data sent, treat descriptions and imported text as untrusted input, and explain which period and report values support each answer. It must not run arbitrary SQL, use a service-role key, expose one organization's records to another, or create, edit, approve, post, or reverse transactions. Financial actions must remain in the normal validated forms and database maker-checker workflow. Any provider, model hosting, retention, and usage cost would need to be evaluated before enabling this feature; no paid AI service is configured or required by the current application.

## Deployment

The application has no Vercel or custom-domain configuration and has not been deployed. After live database verification, configure the same publishable Supabase URL/key as deployment environment variables, set the production Auth callback URL, deploy from the existing GitHub repository, then verify sign-in, protected routes, responsive layouts, and the database workflows. Confirm the hosting provider's current free-tier limits and possible costs before enabling billing or paid features.
