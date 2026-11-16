# Linkora Finance

Linkora Finance is a branded Next.js 16 and TypeScript financial workspace. It preserves the original database foundation and adds incremental database hardening and accounting workflows.

## Supabase target

The selected development and testing target is the existing Free project `jztejhppiepczvqiebik` in the Linkora Finance organization `roszvxdeseeatthlkhwm`. It is hosted in Seoul (`ap-northeast-2`), not Mumbai. A read-only catalog audit found no application tables, custom schemas, Auth users, Storage buckets, or Storage objects. No migration has been applied from this workspace, and no frontend secrets are configured here.

The project is still on the Free plan. Free includes 500 MB database storage, 5 GB egress, 1 GB file storage, and 50,000 monthly active users; projects may pause after a week of low activity. There are no automatic database backups or point-in-time recovery on Free. Do not use this project for production accounting records until backup, recovery, RLS, and real-accounting tests have passed and the availability limitations have been accepted.

## Included

- Responsive Linkora application shell, brand assets, light/dark theme, tables, search, and role-aware navigation.
- Supabase Auth login, registration, password recovery, reset, server-rendered cookie sessions, and protected workspace routes.
- Organization setup and starter chart of accounts through the existing setup RPC.
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

Review the dry-run output carefully. The project must still be the selected Linkora Finance Free project. `db push` applies the historical foundation first, then `20261117000100_extend_workflow_roles.sql`, then `20261117000200_accounting_workflow_and_security.sql`. The enum migration is separate because PostgreSQL requires new enum labels to commit before later migrations use them. Do not run the foundation migration alone as an exposed application; the hardening migration is required before inviting users.

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

`src/lib/supabase/integration.test.ts` is a live smoke-test preparation. It is skipped unless `NEXT_PUBLIC_SUPABASE_URL`, a publishable key, `SUPABASE_TEST_EMAIL`, and `SUPABASE_TEST_PASSWORD` are provided for a dedicated test account. It signs in and reads that account's own memberships; it does not provision synthetic financial records. RLS cross-tenant, journal posting/reversal, period locks, report reconciliation, and migration tests still require a dedicated test organization and live verification.

## Backup and recovery on Free

Supabase Free does not provide automatic database backups, downloadable platform backups, or PITR. Before applying schema changes and on a regular schedule, export the database with the Supabase CLI, encrypt the backup, and store it outside this repository and outside the Supabase project:

```powershell
pnpm dlx supabase@latest db dump --linked --file .\linkora-backup.sql
```

Keep access tightly restricted and remove local copies after transferring them to approved encrypted storage. To recover, restore the dump into a separate disposable local PostgreSQL/Supabase instance first, validate schema and accounting totals there, then plan a reviewed restore to the target project. A database dump does not back up files stored in Supabase Storage; export those separately if Storage is later enabled. The restore process has not yet been exercised, so this is a procedure, not a disaster-recovery guarantee.

## Module status

| Module | Current state |
| --- | --- |
| Auth, organization setup, chart of accounts | UI and Supabase integration implemented; live configuration not verified |
| Journal draft, submit, review queue, approve, reject, post, reverse | Frontend and additive SQL implemented; migrations and live workflow tests pending |
| Ledger, trial balance, P&L, balance sheet, dashboard summaries | Queries and report functions prepared; live reconciliation pending |
| Accounting periods and audit log | Interfaces and additive integrity/audit SQL prepared; live RLS tests pending |
| Income, expenses, invoicing, AR/AP, banking and reconciliation | Development states; transactional schema/workflows not implemented |
| Budgets, fixed assets, multi-currency revaluation, departments/projects, payroll, tax | Development states; not implemented |
| Cash flow statement and advanced exports | Not implemented |

The reports use posted and reversed journal entries. Opening balance workflows, period closing transfers, cash-flow classification, and foreign-currency revaluation are not yet supported; do not represent these reports as IFRS-complete financial statements.

## Free-plan region and limitations

Pakistan users will generally see more network latency from Seoul than from a nearer South Asian region such as Mumbai. Region cannot be changed in place; moving would require creating and validating a separate project and migrating data. Keep the current project rather than taking a data-loss or additional-cost risk solely to change region. Free projects can pause after inactivity, have limited storage/egress, and do not include automatic backups or an uptime SLA.

## Deployment

The application has no Vercel or custom-domain configuration and has not been deployed. After live database verification, configure the same publishable Supabase URL/key as deployment environment variables, set the production Auth callback URL, deploy from the existing GitHub repository, then verify sign-in, protected routes, responsive layouts, and the database workflows. Confirm the hosting provider's current free-tier limits and possible costs before enabling billing or paid features.

