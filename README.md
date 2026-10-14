# Aztek Investment client portal

A Next.js portal for Aztek Investment Company. Clients create an account, request cryptocurrency deposits, monitor managed-account records, and request withdrawals. Authorized staff review payments, record investment activity, and process withdrawals.

The company PDF named in the project brief was not present in this workspace. Public copy uses the stated investment principles and does not invent registration numbers, licenses, addresses, wallet addresses, or performance.

## Configure

1. Copy `.env.example` to `.env.local` and fill in the Supabase URL, anon key, service role key, Resend key, and `EMAIL_FROM`.
2. Apply the database schema. Prefer the Supabase SQL editor:
   - Open **SQL** → New query
   - Paste `supabase/FULL_SETUP.sql` (or run each file in `supabase/migrations` in filename order)
   - Click **Run**
   - Or, if you have a working Database connection string: set `SUPABASE_DB_PASSWORD` and run `npm run db:migrate`
3. In Supabase Auth, set the site URL to `APP_URL` (`http://localhost:3000` locally) and add `/auth/callback` to redirect URLs.
4. Promote an administrator only from the SQL editor after you know the user id:

```sql
update public.profiles
set role = 'admin', account_status = 'active', verification_status = 'verified', email_verified_at = now()
where id = 'USER_ID';
```

Registration cannot set a role. Every new client receives a **$100.00 welcome bonus** as a ledger credit to available cash.

## Funding boundary

Deposits and withdrawals are off by default. Before deposits are enabled:

- Add a receiving wallet in **Admin → Wallets** (address verified outside this app).
- Set minimum, maximum, and enable the asset.
- Turn deposits on in **Admin → Settings**.

Clients see the configured address and a QR code, send payment themselves, upload a receipt, and click **I have paid**. An administrator reviews the receipt and credits the account once. Approving the same deposit again does not post a second credit.

The application never generates a wallet address and never stores a private key or seed phrase. No crypto provider is required for this manual wallet workflow.

## Email

In-app notifications are written with the financial change. Resend sends the matching outbox emails from server actions after signup, deposit creation, payment declaration, and deposit review. You can also call `POST /api/notifications/dispatch` with `Authorization: Bearer CRON_SECRET`. A failed email does not reverse a ledger entry. Subjects do not include wallet addresses.

## Checks

```bash
npm test
npm run typecheck
npm run lint
npm run build
```

## Operations

See `docs/operations.md` for reconciliation, corrections, and the rule that real client funds should not be accepted until legal, custody, and compliance review is complete.
