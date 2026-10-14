-- Aztek Investment client portal
-- Accounting policy:
--   * USD ledger amounts are integer cents. Crypto quantities are numeric.
--   * Client cash, reserved cash, and invested cost are liabilities.
--   * Company custody cash and invested assets are assets.
--   * Fee revenue is equity. Assets should equal liabilities plus fee revenue.
--   * Posted ledger rows are immutable. Corrections use compensating entries.
--   * A deposit request is not a credit. Only review_deposit posts cash.
--   * Moving cash into an investment does not create profit.
--   * Market valuations live on holdings and snapshots, not as invented cash.

create extension if not exists pgcrypto;

create type public.user_role as enum (
  'client', 'support', 'compliance', 'portfolio_manager', 'admin'
);
create type public.account_status as enum (
  'pending', 'active', 'restricted', 'suspended', 'closed'
);
create type public.verification_status as enum (
  'unverified', 'pending_review', 'verified', 'rejected'
);
create type public.deposit_status as enum (
  'draft', 'awaiting_payment', 'payment_detected', 'confirming',
  'under_review', 'credited', 'rejected', 'expired', 'cancelled'
);
create type public.withdrawal_status as enum (
  'requested', 'under_review', 'approved', 'processing',
  'completed', 'rejected', 'cancelled', 'failed'
);
create type public.ledger_account_type as enum (
  'client_cash', 'client_cash_reserved', 'client_investments',
  'company_custody_cash', 'company_invested_assets', 'company_fee_revenue'
);
create type public.ledger_tx_status as enum ('posted');
create type public.investment_category as enum (
  'digital_asset_trading', 'currency_market_operations',
  'diversified_strategies', 'private_business', 'other_managed'
);
create type public.record_status as enum ('open', 'closed', 'cancelled');
create type public.holding_status as enum ('active', 'closed');
create type public.notification_type as enum (
  'deposit_created', 'payment_detected', 'deposit_credited', 'deposit_rejected',
  'withdrawal_requested', 'withdrawal_status_changed', 'investment_record_updated',
  'security_event', 'support_reply', 'account_notice'
);
create type public.support_status as enum ('open', 'pending', 'closed');
create type public.outbox_status as enum (
  'pending', 'sent', 'skipped_unconfigured', 'failed'
);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  country_code text,
  phone text,
  role public.user_role not null default 'client',
  account_status public.account_status not null default 'pending',
  email_verified_at timestamptz,
  verification_status public.verification_status not null default 'unverified',
  notification_preferences jsonb not null default '{"email":true,"in_app":true}'::jsonb,
  onboarding_welcome_at timestamptz,
  onboarding_completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_name_length check (char_length(full_name) <= 120),
  constraint profiles_country_shape check (
    country_code is null or country_code ~ '^[A-Z]{2}$'
  ),
  constraint profiles_phone_length check (phone is null or char_length(phone) <= 32)
);

create table public.app_settings (
  id integer primary key default 1,
  deposits_enabled boolean not null default false,
  withdrawals_enabled boolean not null default false,
  support_email text,
  deposit_notification_email text,
  company_legal_name text not null default 'Aztek Investment Company',
  withdrawal_processing_notice text not null default
    'Withdrawal requests are reviewed individually. Processing time depends on verification and network conditions. A fixed payout window is not guaranteed.',
  deposit_expiry_hours integer not null default 168,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id),
  constraint app_settings_singleton check (id = 1),
  constraint app_settings_expiry_positive check (deposit_expiry_hours between 1 and 720)
);

insert into public.app_settings (id) values (1);

create table public.deposit_assets (
  id uuid primary key default gen_random_uuid(),
  symbol text not null,
  asset_name text not null,
  network_name text not null,
  network_identifier text not null,
  asset_contract text,
  receiving_address text,
  address_is_shared boolean not null default true,
  address_verified_at timestamptz,
  minimum_deposit_cents bigint not null default 0,
  maximum_deposit_cents bigint,
  required_confirmations integer not null default 12,
  deposit_enabled boolean not null default false,
  withdrawal_enabled boolean not null default false,
  withdrawal_fee_cents bigint,
  custody_provider text,
  decimals integer not null default 6,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint deposit_assets_symbol_network unique (symbol, network_identifier),
  constraint deposit_assets_symbol_shape check (symbol ~ '^[A-Z0-9]{2,12}$'),
  constraint deposit_assets_amounts check (
    minimum_deposit_cents >= 0
    and (maximum_deposit_cents is null or maximum_deposit_cents >= minimum_deposit_cents)
  ),
  constraint deposit_assets_confirmations check (required_confirmations >= 1),
  constraint deposit_assets_decimals check (decimals between 0 and 18),
  constraint deposit_assets_enable_deposit check (
    deposit_enabled = false
    or (
      receiving_address is not null
      and char_length(btrim(receiving_address)) between 20 and 128
      and address_verified_at is not null
      and minimum_deposit_cents > 0
      and maximum_deposit_cents is not null
    )
  ),
  constraint deposit_assets_enable_withdrawal check (
    withdrawal_enabled = false
    or (
      receiving_address is not null
      and withdrawal_fee_cents is not null
      and withdrawal_fee_cents >= 0
    )
  )
);

create table public.deposit_requests (
  id uuid primary key default gen_random_uuid(),
  reference text not null unique,
  user_id uuid not null references public.profiles (id),
  requested_amount_cents bigint not null,
  credited_amount_cents bigint,
  asset_id uuid not null references public.deposit_assets (id),
  asset_symbol_snapshot text not null,
  asset_name_snapshot text not null,
  network_name_snapshot text not null,
  network_identifier_snapshot text not null,
  asset_contract_snapshot text,
  expected_crypto_amount numeric(36, 18),
  exchange_rate numeric(36, 18),
  quote_expires_at timestamptz,
  receiving_address_display text not null,
  address_is_shared_snapshot boolean not null default true,
  transaction_hash text,
  observed_crypto_amount numeric(36, 18),
  observed_address text,
  confirmation_count integer,
  status public.deposit_status not null default 'awaiting_payment',
  submitted_at timestamptz,
  credited_at timestamptz,
  rejected_at timestamptz,
  reviewed_by uuid references public.profiles (id),
  review_reason text,
  idempotency_key uuid not null,
  risk_acknowledged_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint deposit_requests_amount_positive check (requested_amount_cents > 0),
  constraint deposit_requests_credit_shape check (
    status <> 'credited'
    or (credited_at is not null and credited_amount_cents is not null and credited_amount_cents > 0)
  ),
  constraint deposit_requests_hash_shape check (
    transaction_hash is null or transaction_hash ~ '^[A-Za-z0-9]{32,128}$'
  ),
  constraint deposit_requests_user_idempotency unique (user_id, idempotency_key)
);

create unique index deposit_requests_network_hash_uidx
  on public.deposit_requests (network_identifier_snapshot, transaction_hash)
  where transaction_hash is not null and status <> 'cancelled';

create index deposit_requests_user_status_idx
  on public.deposit_requests (user_id, status, created_at desc);

create table public.deposit_review_notes (
  id uuid primary key default gen_random_uuid(),
  deposit_id uuid not null references public.deposit_requests (id),
  author_id uuid not null references public.profiles (id),
  note text not null,
  created_at timestamptz not null default now(),
  constraint deposit_review_notes_length check (char_length(note) between 8 and 2000)
);

create table public.blockchain_transactions (
  id uuid primary key default gen_random_uuid(),
  deposit_id uuid references public.deposit_requests (id),
  network_identifier text not null,
  transaction_hash text not null,
  output_index integer not null default 0,
  asset_identifier text not null,
  from_address text,
  to_address text not null,
  raw_amount numeric(36, 18),
  confirmation_count integer not null default 0,
  block_height bigint,
  observed_at timestamptz not null default now(),
  last_checked_at timestamptz not null default now(),
  verification_status text not null default 'observed',
  provider_reference text,
  constraint blockchain_transactions_unique unique (
    network_identifier, transaction_hash, output_index
  ),
  constraint blockchain_transactions_hash_shape check (
    transaction_hash ~ '^[A-Za-z0-9]{32,128}$'
  )
);

create table public.account_ledger_accounts (
  id uuid primary key default gen_random_uuid(),
  account_owner_user_id uuid references public.profiles (id),
  account_type public.ledger_account_type not null,
  asset_or_currency text not null default 'USD',
  status text not null default 'active',
  created_at timestamptz not null default now(),
  constraint ledger_accounts_currency check (asset_or_currency = 'USD')
);

create unique index ledger_client_accounts_uidx
  on public.account_ledger_accounts (account_owner_user_id, account_type)
  where account_owner_user_id is not null;

create unique index ledger_company_accounts_uidx
  on public.account_ledger_accounts (account_type)
  where account_owner_user_id is null;

create table public.ledger_transactions (
  id uuid primary key default gen_random_uuid(),
  reference text not null unique,
  transaction_type text not null,
  source_type text not null,
  source_id uuid,
  status public.ledger_tx_status not null default 'posted',
  description text not null,
  created_by uuid references public.profiles (id),
  idempotency_key text not null unique,
  created_at timestamptz not null default now()
);

create index ledger_transactions_source_idx
  on public.ledger_transactions (source_type, source_id);

create table public.ledger_entries (
  id uuid primary key default gen_random_uuid(),
  ledger_transaction_id uuid not null references public.ledger_transactions (id),
  account_id uuid not null references public.account_ledger_accounts (id),
  debit_amount bigint not null default 0,
  credit_amount bigint not null default 0,
  currency text not null default 'USD',
  created_at timestamptz not null default now(),
  constraint ledger_entries_currency check (currency = 'USD'),
  constraint ledger_entries_one_sided check (
    (debit_amount > 0 and credit_amount = 0)
    or (credit_amount > 0 and debit_amount = 0)
  )
);

create index ledger_entries_account_idx on public.ledger_entries (account_id);
create index ledger_entries_tx_idx on public.ledger_entries (ledger_transaction_id);

create table public.investment_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id),
  activity_reference text not null unique,
  category public.investment_category not null,
  description text not null,
  execution_reference text not null,
  amount_allocated_cents bigint not null,
  asset_or_currency text not null default 'USD',
  executed_at timestamptz,
  recorded_at timestamptz not null default now(),
  recorded_by uuid not null references public.profiles (id),
  status public.record_status not null default 'open',
  evidence_reference text not null,
  realized_result_cents bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint investment_records_amount check (amount_allocated_cents > 0),
  constraint investment_records_description check (char_length(description) >= 8),
  constraint investment_records_evidence check (
    char_length(execution_reference) >= 3 and char_length(evidence_reference) >= 3
  )
);

create index investment_records_user_idx
  on public.investment_records (user_id, recorded_at desc);

create table public.portfolio_holdings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id),
  investment_record_id uuid references public.investment_records (id),
  category public.investment_category not null,
  asset_or_currency text not null default 'USD',
  quantity numeric(36, 18),
  cost_basis_cents bigint,
  current_valuation_cents bigint,
  valuation_currency text not null default 'USD',
  valuation_timestamp timestamptz,
  valuation_source text,
  realized_result_cents bigint,
  status public.holding_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint holdings_currency check (valuation_currency = 'USD'),
  constraint holdings_values check (
    (cost_basis_cents is null or cost_basis_cents >= 0)
    and (current_valuation_cents is null or current_valuation_cents >= 0)
  )
);

create index portfolio_holdings_user_idx
  on public.portfolio_holdings (user_id, status);

create table public.portfolio_valuations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id),
  cash_value_cents bigint not null,
  reserved_value_cents bigint not null default 0,
  holdings_value_cents bigint not null,
  liabilities_value_cents bigint not null default 0,
  total_account_value_cents bigint not null,
  valuation_currency text not null default 'USD',
  valuation_timestamp timestamptz not null default now(),
  valuation_source text not null,
  recorded_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  constraint portfolio_valuations_currency check (valuation_currency = 'USD'),
  constraint portfolio_valuations_total check (
    total_account_value_cents = cash_value_cents + reserved_value_cents + holdings_value_cents - liabilities_value_cents
  )
);

create index portfolio_valuations_user_idx
  on public.portfolio_valuations (user_id, valuation_timestamp desc);

create table public.withdrawal_requests (
  id uuid primary key default gen_random_uuid(),
  reference text not null unique,
  user_id uuid not null references public.profiles (id),
  requested_amount_cents bigint not null,
  currency text not null default 'USD',
  asset_id uuid references public.deposit_assets (id),
  asset_symbol_snapshot text,
  network_name_snapshot text,
  destination_address text,
  network_identifier text,
  fee_amount_cents bigint,
  payout_amount_cents bigint,
  status public.withdrawal_status not null default 'requested',
  reserved_ledger_transaction_id uuid references public.ledger_transactions (id),
  payout_transaction_hash text,
  reviewed_by uuid references public.profiles (id),
  review_reason text,
  requested_at timestamptz not null default now(),
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint withdrawal_amounts check (
    requested_amount_cents > 0
    and currency = 'USD'
    and (fee_amount_cents is null or fee_amount_cents >= 0)
    and (payout_amount_cents is null or payout_amount_cents > 0)
  ),
  constraint withdrawal_completed_shape check (
    status <> 'completed'
    or (
      payout_transaction_hash is not null
      and processed_at is not null
      and payout_amount_cents is not null
    )
  )
);

create index withdrawal_requests_user_idx
  on public.withdrawal_requests (user_id, created_at desc);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  notification_type public.notification_type not null,
  title text not null,
  message text not null,
  related_entity_type text,
  related_entity_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index notifications_user_idx
  on public.notifications (user_id, created_at desc);

create table public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid references public.notifications (id),
  recipient_email text not null,
  subject text not null,
  body text not null,
  status public.outbox_status not null default 'pending',
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references public.profiles (id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  reason text,
  request_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index audit_logs_created_idx on public.audit_logs (created_at desc);
create index audit_logs_entity_idx on public.audit_logs (entity_type, entity_id);

create table public.support_conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id),
  subject text not null,
  status public.support_status not null default 'open',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint support_subject_length check (char_length(subject) between 3 and 160)
);

create table public.support_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.support_conversations (id) on delete cascade,
  sender_user_id uuid not null references public.profiles (id),
  message text not null,
  created_at timestamptz not null default now(),
  constraint support_message_length check (char_length(message) between 1 and 4000)
);

create index support_messages_conversation_idx
  on public.support_messages (conversation_id, created_at);

create table public.contact_inquiries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles (id),
  full_name text not null,
  email text not null,
  message text not null,
  created_at timestamptz not null default now(),
  constraint contact_message_length check (
    char_length(full_name) between 2 and 120
    and char_length(message) between 10 and 4000
  )
);

create table public.rate_limits (
  bucket_key text not null,
  window_start timestamptz not null,
  hit_count integer not null default 0,
  primary key (bucket_key, window_start)
);

insert into public.account_ledger_accounts (account_type, asset_or_currency)
values
  ('company_custody_cash', 'USD'),
  ('company_invested_assets', 'USD'),
  ('company_fee_revenue', 'USD');
