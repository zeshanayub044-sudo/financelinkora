# Linkora Finance

Linkora Finance is a Next.js 16 application built on the existing Phase 1+2 database foundation. It keeps the original migration and accounting rules intact and uses the provided brand tokens and assets.

## Included

- Responsive, branded workspace with organization selection, search, notification panel, profile menu, dark theme, and mobile navigation.
- Supabase Auth login, password recovery, password update, SSR cookie sessions, and protected workspace routes.
- Organization setup using the existing `create_organization(...)` RPC and starter chart of accounts.
- Data-driven dashboard, chart of accounts, journal entries, approval/posting/reversal workflow, general ledger, trial balance, accounting periods, audit log, and approval settings.
- Tailwind CSS 4 and shadcn/ui compatible component tokens, variant primitives, and CLI configuration.
- Search, sorting, and pagination for finance tables; Zod validation and balanced journal calculations.
- Clearly marked development states for modules that have no supporting records or routines in the current migration.

The app uses real Supabase queries only. Without a project URL and anon key, it shows a setup message. With an empty database, the dashboard explains that no posted activity exists; it does not seed example figures.

## Requirements

- Node.js 20.9 or newer (Node.js 24 LTS recommended).
- pnpm 10 or newer.
- A new, dedicated Supabase project for Linkora Finance. This app has not been connected to any project.

## Run locally

```bash
pnpm install
Copy-Item .env.example .env.local
# Fill in the two Supabase values after creating your dedicated project.
pnpm dev
```

Open `http://localhost:3000`. The login recovery flow needs this redirect URL in Supabase Auth: `http://localhost:3000/auth/callback`. Add your production callback URL before deployment.

## Connect a new Supabase project

1. Create a new Supabase organization and project specifically for Linkora Finance. Do not reuse an unrelated project.
2. In the new project's SQL Editor, run the existing `supabase/migrations/0001_foundation_and_ledger.sql` migration. This app does not replace or amend that migration.
3. In Supabase Auth, enable email sign-in. Configure the Site URL and redirect allowlist to include `http://localhost:3000/auth/callback` and the production `/auth/callback` URL when deployed. Enable leaked-password protection and MFA according to your organization's policy.
4. Copy the project URL and publishable/anon key from the new project's API settings into `.env.local`:

   ```env
   NEXT_PUBLIC_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
   NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
   ```

5. Restart `pnpm dev`, create an account through Supabase Auth, then sign in. The app calls the migration's `create_organization(...)` function to create the organization, owner membership, and starter chart of accounts.
6. Invite a second authorized member before testing maker-checker approval. Approval is denied when the creator tries to approve their own journal entry.
7. Create a balanced draft, approve it as a different authorized user, and post it. Verify it appears in the general ledger and trial balance. Test closed accounting periods and a reversal as separate workflows.

The app reads the current `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` and also accepts the legacy `NEXT_PUBLIC_SUPABASE_ANON_KEY` name. Only a publishable/anon key is used by the app. No service-role key is required or accepted by the frontend. Do not put service-role or secret keys in `NEXT_PUBLIC_*` variables.

## Accounting behavior and current database limits

- Journal drafts are created with their lines through the authenticated Supabase session. The app checks balance on the client and server; database functions and triggers remain the final authority.
- Approve and post calls use the existing `approve_journal_entry` and `post_journal_entry` RPCs. Reversals use `reverse_journal_entry`.
- The migration has `draft`, `approved`, `posted`, and `reversed` statuses. It has no rejected status or submit/reject RPC, so the app does not simulate rejection. Drafts are shown in the review queue and authorized users can approve them directly.
- Existing account and period policies are honored. The migration supports account creation but the UI does not offer account editing/deletion. Audit triggers cover accounts, journal entries, and organization updates; the audit page describes this scope.
- Existing reports are the `ledger` view and `trial_balance(...)` function. The UI does not invent invoices, bank reconciliation, budgets, tax schedules, payroll, or financial statements that the migration cannot store.
- The migration includes entry currency and exchange-rate fields, but its trial-balance function does not convert currencies. The application therefore enforces the organization base currency for new journal entries until FX reporting is implemented.

## Checks

Local checks:

```bash
pnpm typecheck
pnpm test
pnpm lint
pnpm build
```

Vitest tests cover UI components, authentication form behavior/validation, journal balancing, and form validation. Responsive navigation has a component check; also inspect the app at narrow phone, tablet, and desktop widths when a Supabase project is connected.

Live-Supabase checks are intentionally not run until a new project and test users are configured. Exercise sign-in/recovery, RLS membership boundaries, maker-checker approval, posting restrictions, closed periods, reversal, audit visibility, and trial-balance totals using test accounts with different roles. Never use a service-role key for these checks.

## Modules

Operational against the current migration: chart of accounts (read/create), journal entries (draft/create, approve, post, reverse), general ledger, trial balance, accounting periods (read/create/close/reopen), audit log, dashboard, authentication, and approval setting.

Development states pending backend support: income, expenses, banking/reconciliation, customers, suppliers, invoices, payments, budgets, cash flow, financial statements, projects, departments, fixed assets, tax management, payroll, and extended financial reports.
