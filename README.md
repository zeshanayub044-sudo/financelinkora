# Linkora Finance — Phase 1+2 (database + brand foundation)

## Status
Included: schema, RBAC, RLS, audit log, chart of accounts, double-entry posting engine, ledger view, trial balance, setup RPC, brand tokens and logos.
NOT yet built: Next.js UI, income/expenses/banking/AR/AP, reports beyond trial balance, tests. Nothing here is connected to Supabase until you do the steps below.

## Setup (new, separate Supabase org)
1. supabase.com -> New organization -> New project (do not reuse existing ones).
2. SQL Editor -> run supabase/migrations/0001_foundation_and_ledger.sql
3. Auth -> enable email, turn on leaked-password protection and MFA.
4. Copy URL + anon key into .env.local (see .env.example). Keep the service-role key server-side only.
5. Scaffold the app: npx create-next-app@latest --ts --tailwind, then add shadcn/ui, copy public/brand and src/styles/brand.css, merge tailwind.brand.ts.
6. Sign up, then call rpc create_organization(...) (PKR is the suggested base currency).

## Accounting rules enforced in the database
- Entries start as draft. Posting needs >=2 lines, debits = credits (4 dp), active accounts, open period.
- Maker-checker: approver must differ from creator (toggle: organizations.require_approval).
- Posted entries and lines are immutable and undeletable; corrections use reverse_journal_entry() (creates an opposite posted entry, marks the original reversed).
- Reports read only posted/reversed entries (ledger view, trial_balance()).
- audit_logs is append-only for app users; written by triggers.
- Money is numeric(20,4); no floats.

## Assumptions / limits
- Multi-currency fields exist on entries; FX revaluation is Phase 5. Lines are stored in one currency per entry.
- Reversal is a single authorized action (audited), not separately approved.
- Starter chart of accounts is editable; tax setup is deferred to Phase 5.
- Migration is untested against a live instance; run it on the new empty project first and report any error.
