-- ===== 20261014120000_schema.sql =====
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


-- ===== 20261014120100_functions.sql =====
-- Trusted financial functions. Callers cannot post ledger rows directly.
-- Every function pins search_path. Privilege changes require app.trusted_profile_write
-- set inside an authorized function, or the auth trigger path.

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.protect_profile()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  actor_role public.user_role;
  privileged boolean;
begin
  if current_setting('app.trusted_profile_write', true) = '1' then
    new.updated_at := now();
    return new;
  end if;

  privileged := tg_op = 'UPDATE' and (
    new.role is distinct from old.role
    or new.account_status is distinct from old.account_status
    or new.verification_status is distinct from old.verification_status
    or new.email_verified_at is distinct from old.email_verified_at
    or new.id is distinct from old.id
  );

  if tg_op = 'INSERT' then
    privileged := new.role is distinct from 'client'
      or new.account_status is distinct from 'pending'
      or new.verification_status is distinct from 'unverified'
      or new.email_verified_at is not null;
  end if;

  if privileged then
    if auth.uid() is null
       and current_user in ('postgres', 'supabase_admin', 'service_role') then
      new.updated_at := now();
      return new;
    end if;
    select role into actor_role from public.profiles where id = auth.uid();
    if actor_role is distinct from 'admin' then
      raise exception 'Only an administrator can change account privileges.';
    end if;
  end if;

  if tg_op = 'UPDATE' then
    new.updated_at := now();
  end if;
  return new;
end;
$$;

create or replace function public.prevent_append_only_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'This record is append-only and cannot be changed.';
end;
$$;

create or replace function public.enforce_ledger_balance()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  debit_sum bigint;
  credit_sum bigint;
  tx_id uuid;
begin
  tx_id := coalesce(new.ledger_transaction_id, old.ledger_transaction_id);
  select coalesce(sum(debit_amount), 0), coalesce(sum(credit_amount), 0)
    into debit_sum, credit_sum
  from public.ledger_entries
  where ledger_transaction_id = tx_id;

  if debit_sum <> credit_sum then
    raise exception 'Ledger transaction is unbalanced.';
  end if;
  if debit_sum = 0 then
    raise exception 'Ledger transaction has no value.';
  end if;
  return null;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, country_code, role, account_status, verification_status)
  values (
    new.id,
    left(coalesce(new.raw_user_meta_data ->> 'full_name', ''), 120),
    nullif(upper(coalesce(new.raw_user_meta_data ->> 'country_code', '')), ''),
    'client',
    'pending',
    'unverified'
  );

  insert into public.account_ledger_accounts (account_owner_user_id, account_type)
  values
    (new.id, 'client_cash'),
    (new.id, 'client_cash_reserved'),
    (new.id, 'client_investments');

  return new;
end;
$$;

create or replace function public.sync_email_verification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.email_confirmed_at is not null
     and new.email_confirmed_at is distinct from old.email_confirmed_at then
    perform set_config('app.trusted_profile_write', '1', true);
    update public.profiles
      set email_verified_at = new.email_confirmed_at
    where id = new.id;
  end if;
  return new;
end;
$$;

create trigger profiles_protect
  before insert or update on public.profiles
  for each row execute function public.protect_profile();

create trigger profiles_touch
  before update on public.profiles
  for each row execute function public.touch_updated_at();

create trigger deposit_assets_touch
  before update on public.deposit_assets
  for each row execute function public.touch_updated_at();
create trigger deposit_requests_touch
  before update on public.deposit_requests
  for each row execute function public.touch_updated_at();
create trigger investment_records_touch
  before update on public.investment_records
  for each row execute function public.touch_updated_at();
create trigger portfolio_holdings_touch
  before update on public.portfolio_holdings
  for each row execute function public.touch_updated_at();
create trigger withdrawal_requests_touch
  before update on public.withdrawal_requests
  for each row execute function public.touch_updated_at();
create trigger support_conversations_touch
  before update on public.support_conversations
  for each row execute function public.touch_updated_at();

create trigger ledger_transactions_immutable
  before update or delete on public.ledger_transactions
  for each row execute function public.prevent_append_only_mutation();
create trigger ledger_entries_immutable
  before update or delete on public.ledger_entries
  for each row execute function public.prevent_append_only_mutation();
create trigger audit_logs_immutable
  before update or delete on public.audit_logs
  for each row execute function public.prevent_append_only_mutation();
create trigger portfolio_valuations_immutable
  before update or delete on public.portfolio_valuations
  for each row execute function public.prevent_append_only_mutation();

create constraint trigger ledger_entries_balanced
  after insert or update or delete on public.ledger_entries
  deferrable initially deferred
  for each row execute function public.enforce_ledger_balance();

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create trigger on_auth_user_email_verified
  after update of email_confirmed_at on auth.users
  for each row execute function public.sync_email_verification();

create or replace function public.actor_role()
returns public.user_role
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and account_status not in ('suspended', 'closed')
  );
$$;

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('support', 'compliance', 'portfolio_manager', 'admin')
      and account_status not in ('suspended', 'closed')
  );
$$;

create or replace function public.can_view_clients()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_staff();
$$;

create or replace function public.can_view_ledger()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_staff();
$$;

create or replace function public.can_review_verification()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('admin', 'compliance')
      and account_status not in ('suspended', 'closed')
  );
$$;

create or replace function public.can_manage_investments()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('admin', 'portfolio_manager')
      and account_status not in ('suspended', 'closed')
  );
$$;

create or replace function public.can_support()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('admin', 'support')
      and account_status not in ('suspended', 'closed')
  );
$$;

create or replace function public.require_user()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  status public.account_status;
begin
  if uid is null then
    raise exception 'Authentication required.';
  end if;
  select account_status into status from public.profiles where id = uid;
  if status is null then
    raise exception 'Account profile is not ready yet.';
  end if;
  if status in ('suspended', 'closed') then
    raise exception 'This account cannot perform that action.';
  end if;
  return uid;
end;
$$;

create or replace function public.client_can_fund(target_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = target_user
      and role = 'client'
      and account_status = 'active'
      and verification_status = 'verified'
      and email_verified_at is not null
  );
$$;

create or replace function public.consume_rate_limit(bucket_key text, max_hits integer, window_seconds integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  bucket_window timestamptz;
  current_count integer;
begin
  bucket_window := to_timestamp(
    floor(extract(epoch from now()) / window_seconds) * window_seconds
  );
  insert into public.rate_limits as rl (bucket_key, window_start, hit_count)
  values (consume_rate_limit.bucket_key, bucket_window, 1)
  on conflict (bucket_key, window_start)
  do update set hit_count = rl.hit_count + 1
  returning hit_count into current_count;

  if current_count > max_hits then
    raise exception 'Too many requests. Please wait and try again.';
  end if;
end;
$$;

create or replace function public.write_audit(
  actor uuid,
  action text,
  entity_type text,
  entity_id uuid,
  reason text,
  metadata jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  clean jsonb;
begin
  clean := coalesce(metadata, '{}'::jsonb)
    - 'password' - 'token' - 'access_token' - 'refresh_token'
    - 'secret' - 'private_key' - 'seed' - 'seed_phrase' - 'service_role';
  insert into public.audit_logs (actor_user_id, action, entity_type, entity_id, reason, metadata)
  values (actor, action, entity_type, entity_id, reason, clean);
end;
$$;

create or replace function public.notify_user(
  target_user uuid,
  kind public.notification_type,
  title text,
  message text,
  entity_type text,
  entity_id uuid,
  email_subject text,
  email_body text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  prefs jsonb;
  recipient text;
  note_id uuid;
begin
  select notification_preferences into prefs from public.profiles where id = target_user;
  insert into public.notifications (
    user_id, notification_type, title, message, related_entity_type, related_entity_id
  ) values (
    target_user, kind, title, message, entity_type, entity_id
  ) returning id into note_id;

  if email_subject is not null and coalesce(prefs ->> 'email', 'true') = 'true' then
    select email into recipient from auth.users where id = target_user;
    if recipient is not null then
      insert into public.notification_outbox (notification_id, recipient_email, subject, body)
      values (note_id, recipient, email_subject, email_body);
    end if;
  end if;
end;
$$;

create or replace function public.notify_admins(
  kind public.notification_type,
  title text,
  message text,
  entity_type text,
  entity_id uuid,
  mailbox_subject text,
  mailbox_body text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_id uuid;
  mailbox text;
begin
  for admin_id in
    select id from public.profiles
    where role = 'admin' and account_status = 'active'
  loop
    perform public.notify_user(
      admin_id, kind, title, message, entity_type, entity_id, mailbox_subject, mailbox_body
    );
  end loop;

  select deposit_notification_email into mailbox from public.app_settings where id = 1;
  if mailbox is not null and mailbox_subject is not null then
    insert into public.notification_outbox (recipient_email, subject, body)
    values (mailbox, mailbox_subject, mailbox_body);
  end if;
end;
$$;

create or replace function public.company_account(kind public.ledger_account_type)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.account_ledger_accounts
  where account_owner_user_id is null and account_type = kind
  limit 1;
$$;

create or replace function public.lock_client_account(
  target_user uuid,
  kind public.ledger_account_type
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  account_id uuid;
begin
  select id into account_id
  from public.account_ledger_accounts
  where account_owner_user_id = target_user and account_type = kind
  for update;
  if account_id is null then
    raise exception 'Ledger account is missing.';
  end if;
  return account_id;
end;
$$;

create or replace function public.liability_balance(target_account uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(credit_amount - debit_amount), 0)::bigint
  from public.ledger_entries
  where account_id = target_account;
$$;

create or replace function public.asset_balance(target_account uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(debit_amount - credit_amount), 0)::bigint
  from public.ledger_entries
  where account_id = target_account;
$$;

create or replace function public.begin_ledger(
  tx_type text,
  source_type text,
  source_id uuid,
  description text,
  idempotency_key text,
  actor uuid
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_id uuid;
  new_id uuid;
  ref text;
begin
  select id into existing_id
  from public.ledger_transactions
  where ledger_transactions.idempotency_key = begin_ledger.idempotency_key;

  if existing_id is not null then
    return null;
  end if;

  ref := upper(tx_type) || '-' || to_char(now() at time zone 'utc', 'YYYYMMDD')
    || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  insert into public.ledger_transactions (
    reference, transaction_type, source_type, source_id, status, description, created_by, idempotency_key
  ) values (
    ref, tx_type, source_type, source_id, 'posted', description, actor, idempotency_key
  ) returning id into new_id;

  return new_id;
end;
$$;

create or replace function public.add_ledger_leg(
  ledger_transaction_id uuid,
  account_id uuid,
  debit_amount bigint,
  credit_amount bigint
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (
    (debit_amount > 0 and credit_amount = 0)
    or (credit_amount > 0 and debit_amount = 0)
  ) then
    raise exception 'Ledger leg must be a single-sided positive amount.';
  end if;

  insert into public.ledger_entries (
    ledger_transaction_id, account_id, debit_amount, credit_amount, currency
  ) values (
    add_ledger_leg.ledger_transaction_id,
    add_ledger_leg.account_id,
    add_ledger_leg.debit_amount,
    add_ledger_leg.credit_amount,
    'USD'
  );
end;
$$;

create or replace function public.make_reference(prefix text)
returns text
language sql
volatile
set search_path = public
as $$
  select prefix || '-' || to_char(now() at time zone 'utc', 'YYYYMMDD')
    || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
$$;

create or replace function public.record_valuation_snapshot(
  target_user uuid,
  valuation_source text,
  actor uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  cash_cents bigint;
  reserved_cents bigint;
  holdings_cents bigint;
begin
  cash_cents := public.liability_balance(public.lock_client_account(target_user, 'client_cash'));
  reserved_cents := public.liability_balance(public.lock_client_account(target_user, 'client_cash_reserved'));
  select coalesce(sum(current_valuation_cents), 0)::bigint into holdings_cents
  from public.portfolio_holdings
  where user_id = target_user and status = 'active' and current_valuation_cents is not null;

  insert into public.portfolio_valuations (
    user_id, cash_value_cents, reserved_value_cents, holdings_value_cents,
    liabilities_value_cents, total_account_value_cents, valuation_source, recorded_by
  ) values (
    target_user, cash_cents, reserved_cents, holdings_cents, 0,
    cash_cents + reserved_cents + holdings_cents, valuation_source, actor
  );
end;
$$;


-- ===== 20261014120200_workflows.sql =====
-- Client, deposit, ledger, investment, and withdrawal workflows.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  country text;
begin
  country := upper(coalesce(new.raw_user_meta_data ->> 'country_code', ''));
  if country !~ '^[A-Z]{2}$' then
    country := null;
  end if;

  insert into public.profiles (id, full_name, country_code)
  values (new.id, left(coalesce(new.raw_user_meta_data ->> 'full_name', ''), 120), country)
  on conflict (id) do nothing;

  insert into public.account_ledger_accounts (account_owner_user_id, account_type)
  values
    (new.id, 'client_cash'),
    (new.id, 'client_cash_reserved'),
    (new.id, 'client_investments')
  on conflict (account_owner_user_id, account_type) where account_owner_user_id is not null
  do nothing;

  return new;
end;
$$;

create or replace function public.assert_destination_address(value text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  cleaned text := btrim(value);
begin
  if cleaned ~ '\s' or cleaned ~* '(seed phrase|mnemonic|private key|secret key)' then
    raise exception 'Enter a receiving address. Never send a seed phrase or private key.';
  end if;
  if cleaned !~ '^[A-Za-z0-9]{20,128}$' then
    raise exception 'The receiving address does not look valid for a configured network.';
  end if;
  if cleaned ~* '^[0-9a-f]{64}$' or cleaned ~* '^0x[0-9a-f]{64}$' then
    raise exception 'That value looks like a private key. Enter only the receiving address.';
  end if;
  return cleaned;
end;
$$;

create or replace function public.assert_tx_hash(value text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  cleaned text := btrim(value);
begin
  if cleaned ~ '\s' or cleaned ~* '(seed phrase|mnemonic|private key|secret key)' then
    raise exception 'Enter the transaction hash. Never send a seed phrase or private key.';
  end if;
  if cleaned !~ '^[A-Za-z0-9]{32,128}$' then
    raise exception 'Enter the transaction hash from your wallet receipt.';
  end if;
  return cleaned;
end;
$$;

create or replace function public.get_public_settings()
returns table (
  deposits_enabled boolean,
  withdrawals_enabled boolean,
  withdrawal_processing_notice text,
  company_legal_name text,
  deposit_expiry_hours integer,
  support_email text
)
language sql
stable
security definer
set search_path = public
as $$
  select deposits_enabled, withdrawals_enabled, withdrawal_processing_notice,
         company_legal_name, deposit_expiry_hours, support_email
  from public.app_settings
  where id = 1;
$$;

create or replace function public.update_own_profile(
  full_name text,
  country_code text,
  phone text,
  email_notifications boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := public.require_user();
  country text := upper(btrim(full_name));
begin
  if char_length(btrim(full_name)) < 2 then
    raise exception 'Enter your full legal name.';
  end if;
  country := upper(btrim(country_code));
  if country !~ '^[A-Z]{2}$' then
    raise exception 'Choose your country of residence.';
  end if;
  if phone is not null and btrim(phone) <> '' and btrim(phone) !~ '^\+?[0-9 ()-]{7,32}$' then
    raise exception 'Enter a valid phone number or leave it blank.';
  end if;

  update public.profiles
    set full_name = left(btrim(update_own_profile.full_name), 120),
        country_code = country,
        phone = nullif(btrim(coalesce(phone, '')), ''),
        notification_preferences = jsonb_build_object(
          'email', email_notifications,
          'in_app', true
        )
  where id = uid;
end;
$$;

create or replace function public.acknowledge_welcome()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := public.require_user();
begin
  update public.profiles
    set onboarding_welcome_at = coalesce(onboarding_welcome_at, now())
  where id = uid;
end;
$$;

create or replace function public.complete_onboarding()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := public.require_user();
  profile public.profiles;
begin
  select * into profile from public.profiles where id = uid;
  if profile.onboarding_welcome_at is null then
    raise exception 'Read the account overview before continuing.';
  end if;
  if char_length(btrim(profile.full_name)) < 2 or profile.country_code is null then
    raise exception 'Complete your profile before finishing setup.';
  end if;
  update public.profiles
    set onboarding_completed_at = coalesce(onboarding_completed_at, now())
  where id = uid;
end;
$$;

create or replace function public.request_account_review()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := public.require_user();
  profile public.profiles;
begin
  select * into profile from public.profiles where id = uid;
  if profile.email_verified_at is null then
    raise exception 'Verify your email before requesting account review.';
  end if;
  if char_length(btrim(profile.full_name)) < 2 or profile.country_code is null then
    raise exception 'Complete your profile before requesting account review.';
  end if;
  if profile.verification_status = 'verified' then
    return;
  end if;
  if profile.verification_status = 'pending_review' then
    return;
  end if;

  perform set_config('app.trusted_profile_write', '1', true);
  update public.profiles
    set verification_status = 'pending_review'
  where id = uid;

  perform public.write_audit(uid, 'verification_requested', 'profile', uid, null, '{}'::jsonb);
  perform public.notify_admins(
    'account_notice',
    'Account review requested',
    'A client submitted an account for review.',
    'profile',
    uid,
    'Aztek account review requested',
    'A client account is waiting for review. Sign in to the admin dashboard to continue.'
  );
end;
$$;

create or replace function public.admin_set_verification(
  target_user uuid,
  next_status public.verification_status,
  reason text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := public.require_user();
begin
  if not public.can_review_verification() then
    raise exception 'You do not have permission to review accounts.';
  end if;
  if next_status not in ('verified', 'rejected', 'pending_review') then
    raise exception 'Choose a valid verification decision.';
  end if;
  if char_length(btrim(coalesce(reason, ''))) < 8 then
    raise exception 'Enter a reason for this verification decision.';
  end if;

  perform set_config('app.trusted_profile_write', '1', true);
  update public.profiles
    set verification_status = next_status,
        account_status = case
          when next_status = 'verified' and account_status = 'pending' then 'active'::public.account_status
          else account_status
        end
  where id = target_user and role = 'client';

  if not found then
    raise exception 'Client account was not found.';
  end if;

  perform public.write_audit(actor, 'verification_decision', 'profile', target_user, btrim(reason),
    jsonb_build_object('status', next_status));
  perform public.notify_user(
    target_user,
    'account_notice',
    'Account review updated',
    case
      when next_status = 'verified' then 'Your account review is complete. You can now submit a deposit if funding is open.'
      when next_status = 'rejected' then 'Your account review could not be approved. ' || btrim(reason)
      else 'Your account review status was updated.'
    end,
    'profile',
    target_user,
    'Your Aztek account review was updated',
    'Sign in to your Aztek account to view the latest account status. This email does not include personal documents.'
  );
end;
$$;

create or replace function public.admin_set_account_status(
  target_user uuid,
  next_status public.account_status,
  reason text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := public.require_user();
begin
  if not public.is_admin() then
    raise exception 'You do not have permission to change account status.';
  end if;
  if target_user = actor and next_status in ('suspended', 'closed') then
    raise exception 'You cannot suspend or close your own administrator account.';
  end if;
  if char_length(btrim(coalesce(reason, ''))) < 8 then
    raise exception 'Enter a reason for this account status change.';
  end if;

  perform set_config('app.trusted_profile_write', '1', true);
  update public.profiles
    set account_status = next_status
  where id = target_user;

  if not found then
    raise exception 'Account was not found.';
  end if;

  perform public.write_audit(actor, 'account_status_changed', 'profile', target_user, btrim(reason),
    jsonb_build_object('status', next_status));
end;
$$;

create or replace function public.expire_my_stale_deposits()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  hours integer;
begin
  if uid is null then
    return;
  end if;
  select deposit_expiry_hours into hours from public.app_settings where id = 1;
  update public.deposit_requests
    set status = 'expired'
  where user_id = uid
    and status = 'awaiting_payment'
    and transaction_hash is null
    and created_at < now() - make_interval(hours => hours);
end;
$$;

create or replace function public.create_deposit_request(
  amount_cents bigint,
  asset_id uuid,
  idempotency_key uuid,
  risk_acknowledged boolean
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := public.require_user();
  asset public.deposit_assets;
  existing_id uuid;
  new_id uuid;
  ref text;
  deposits_open boolean;
begin
  perform public.consume_rate_limit('deposit:' || uid::text, 8, 3600);
  if risk_acknowledged is distinct from true then
    raise exception 'Confirm that you understand a cryptocurrency transfer can be irreversible.';
  end if;
  if amount_cents is null or amount_cents <= 0 then
    raise exception 'Enter a deposit amount greater than zero.';
  end if;
  if not public.client_can_fund(uid) then
    raise exception 'Funding opens after your email is verified and your account is approved.';
  end if;

  select deposits_enabled into deposits_open from public.app_settings where id = 1;
  if deposits_open is distinct from true then
    raise exception 'Deposits are not currently open.';
  end if;

  select * into asset
  from public.deposit_assets
  where id = create_deposit_request.asset_id
  for update;

  if asset.id is null or asset.deposit_enabled is distinct from true then
    raise exception 'That asset and network is not available for deposits.';
  end if;
  if amount_cents < asset.minimum_deposit_cents or amount_cents > asset.maximum_deposit_cents then
    raise exception 'The amount is outside the configured minimum and maximum for this asset.';
  end if;

  select id into existing_id
  from public.deposit_requests
  where user_id = uid and deposit_requests.idempotency_key = create_deposit_request.idempotency_key;
  if existing_id is not null then
    return existing_id;
  end if;

  ref := public.make_reference('DEP');
  insert into public.deposit_requests (
    reference, user_id, requested_amount_cents, asset_id,
    asset_symbol_snapshot, asset_name_snapshot, network_name_snapshot,
    network_identifier_snapshot, asset_contract_snapshot,
    receiving_address_display, address_is_shared_snapshot,
    status, idempotency_key, risk_acknowledged_at, submitted_at
  ) values (
    ref, uid, amount_cents, asset.id,
    asset.symbol, asset.asset_name, asset.network_name,
    asset.network_identifier, asset.asset_contract,
    asset.receiving_address, asset.address_is_shared,
    'awaiting_payment', idempotency_key, now(), now()
  ) returning id into new_id;

  perform public.write_audit(uid, 'deposit_created', 'deposit_request', new_id, null,
    jsonb_build_object('reference', ref, 'amount_cents', amount_cents, 'asset', asset.symbol, 'network', asset.network_identifier));
  perform public.notify_admins(
    'deposit_created',
    'New deposit request',
    'A client created deposit ' || ref || '.',
    'deposit_request',
    new_id,
    'New Aztek deposit request',
    'A deposit request is waiting for payment. Review it in the admin dashboard. This email does not include a wallet address.'
  );
  perform public.notify_user(
    uid,
    'deposit_created',
    'Deposit request created',
    'Your deposit request ' || ref || ' was created. Your account will be credited only after the payment is verified.',
    'deposit_request',
    new_id,
    'Your Aztek deposit request was created',
    'Your deposit request was created. Sign in to view payment instructions. Your account is not credited until the payment is verified.'
  );

  return new_id;
end;
$$;

create or replace function public.submit_deposit_transaction_hash(
  deposit_id uuid,
  transaction_hash text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := public.require_user();
  deposit public.deposit_requests;
  cleaned text;
begin
  perform public.consume_rate_limit('deposit-hash:' || uid::text, 20, 3600);
  cleaned := public.assert_tx_hash(transaction_hash);

  select * into deposit
  from public.deposit_requests
  where id = submit_deposit_transaction_hash.deposit_id
  for update;

  if deposit.id is null or deposit.user_id <> uid then
    raise exception 'Deposit request was not found.';
  end if;
  if deposit.status not in ('awaiting_payment', 'payment_detected', 'confirming', 'under_review') then
    raise exception 'This deposit can no longer accept a transaction hash.';
  end if;

  update public.deposit_requests
    set transaction_hash = cleaned,
        status = 'under_review',
        submitted_at = coalesce(submitted_at, now())
  where id = deposit.id;

  perform public.write_audit(uid, 'deposit_hash_submitted', 'deposit_request', deposit.id, null,
    jsonb_build_object('reference', deposit.reference));
  perform public.notify_admins(
    'payment_detected',
    'Deposit hash submitted',
    'A client submitted a transaction hash for ' || deposit.reference || '. It is not credited yet.',
    'deposit_request',
    deposit.id,
    'Aztek deposit needs review',
    'A client submitted a transaction hash. Review the payment before crediting the account.'
  );
end;
$$;

create or replace function public.cancel_deposit_request(deposit_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := public.require_user();
begin
  update public.deposit_requests
    set status = 'cancelled'
  where id = cancel_deposit_request.deposit_id
    and user_id = uid
    and status = 'awaiting_payment'
    and transaction_hash is null;

  if not found then
    raise exception 'Only an unpaid deposit request can be cancelled.';
  end if;
  perform public.write_audit(uid, 'deposit_cancelled', 'deposit_request', deposit_id, null, '{}'::jsonb);
end;
$$;

create or replace function public.review_deposit(
  deposit_id uuid,
  decision text,
  reason text,
  credit_amount_cents bigint,
  observed_crypto_amount numeric,
  confirmation_count integer,
  observed_address text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := public.require_user();
  deposit public.deposit_requests;
  asset public.deposit_assets;
  tx_id uuid;
  cash_account uuid;
  custody_account uuid;
  note text := btrim(coalesce(reason, ''));
  linked_deposit uuid;
begin
  if not public.is_admin() then
    raise exception 'You do not have permission to review deposits.';
  end if;
  if char_length(note) < 8 then
    raise exception 'Enter a reason for this deposit decision.';
  end if;
  if decision not in ('approve', 'reject', 'flag') then
    raise exception 'Choose a valid deposit decision.';
  end if;

  select * into deposit from public.deposit_requests where id = review_deposit.deposit_id for update;
  if deposit.id is null then
    raise exception 'Deposit request was not found.';
  end if;
  if deposit.status = 'credited' and decision = 'approve' then
    return;
  end if;
  if deposit.status not in ('awaiting_payment', 'payment_detected', 'confirming', 'under_review') then
    raise exception 'This deposit can no longer be reviewed.';
  end if;

  insert into public.deposit_review_notes (deposit_id, author_id, note)
  values (deposit.id, actor, note);

  if decision = 'flag' then
    update public.deposit_requests
      set status = 'under_review', reviewed_by = actor
    where id = deposit.id;
    perform public.write_audit(actor, 'deposit_flagged', 'deposit_request', deposit.id, note, '{}'::jsonb);
    return;
  end if;

  if decision = 'reject' then
    update public.deposit_requests
      set status = 'rejected', rejected_at = now(), reviewed_by = actor, review_reason = note
    where id = deposit.id;
    perform public.write_audit(actor, 'deposit_rejected', 'deposit_request', deposit.id, note, '{}'::jsonb);
    perform public.notify_user(
      deposit.user_id, 'deposit_rejected', 'Deposit could not be approved',
      'Deposit ' || deposit.reference || ' could not be approved. ' || note,
      'deposit_request', deposit.id,
      'Your Aztek deposit could not be approved',
      'Sign in to view the reason your deposit was not approved.'
    );
    return;
  end if;

  if deposit.transaction_hash is null then
    raise exception 'A transaction hash is required before a deposit can be credited.';
  end if;
  if observed_crypto_amount is null or observed_crypto_amount <= 0 then
    raise exception 'Enter the cryptocurrency amount observed on the transfer.';
  end if;
  if credit_amount_cents is null or credit_amount_cents <= 0 then
    raise exception 'Enter the USD amount to credit after verification.';
  end if;

  select * into asset from public.deposit_assets where id = deposit.asset_id;
  if confirmation_count is null or confirmation_count < asset.required_confirmations then
    raise exception 'The transfer has not reached the required confirmation count.';
  end if;
  if observed_address is not null and btrim(observed_address) <> deposit.receiving_address_display then
    raise exception 'The observed receiving address does not match the deposit instructions. Flag the payment instead of crediting it.';
  end if;

  select deposit_id into linked_deposit
  from public.blockchain_transactions
  where network_identifier = deposit.network_identifier_snapshot
    and transaction_hash = deposit.transaction_hash
    and output_index = 0;
  if linked_deposit is not null and linked_deposit <> deposit.id then
    raise exception 'This transaction hash is already linked to another deposit.';
  end if;

  tx_id := public.begin_ledger(
    'deposit_credit', 'deposit_request', deposit.id,
    'Deposit credited ' || deposit.reference,
    'deposit-credit:' || deposit.id::text,
    actor
  );
  if tx_id is not null then
    cash_account := public.lock_client_account(deposit.user_id, 'client_cash');
    custody_account := public.company_account('company_custody_cash');
    perform public.add_ledger_leg(tx_id, custody_account, credit_amount_cents, 0);
    perform public.add_ledger_leg(tx_id, cash_account, 0, credit_amount_cents);
  end if;

  insert into public.blockchain_transactions (
    deposit_id, network_identifier, transaction_hash, output_index, asset_identifier,
    to_address, raw_amount, confirmation_count, verification_status
  ) values (
    deposit.id, deposit.network_identifier_snapshot, deposit.transaction_hash, 0,
    deposit.asset_symbol_snapshot, deposit.receiving_address_display,
    observed_crypto_amount, confirmation_count, 'matched'
  )
  on conflict (network_identifier, transaction_hash, output_index)
  do update set
    confirmation_count = excluded.confirmation_count,
    raw_amount = excluded.raw_amount,
    last_checked_at = now(),
    verification_status = 'matched',
    deposit_id = excluded.deposit_id;

  update public.deposit_requests
    set status = 'credited',
        credited_at = coalesce(credited_at, now()),
        credited_amount_cents = credit_amount_cents,
        observed_crypto_amount = review_deposit.observed_crypto_amount,
        observed_address = coalesce(btrim(observed_address), receiving_address_display),
        confirmation_count = review_deposit.confirmation_count,
        reviewed_by = actor
  where id = deposit.id;

  perform public.write_audit(actor, 'deposit_credited', 'deposit_request', deposit.id, note,
    jsonb_build_object('credit_amount_cents', credit_amount_cents, 'requested_amount_cents', deposit.requested_amount_cents));
  perform public.notify_user(
    deposit.user_id, 'deposit_credited', 'Deposit credited',
    'Deposit ' || deposit.reference || ' has been confirmed and credited to your account.',
    'deposit_request', deposit.id,
    'Your Aztek deposit was credited',
    'Your deposit has been confirmed and credited. Sign in to view your account. This email does not include a wallet address.'
  );
end;
$$;


-- ===== 20261014120300_operations.sql =====
-- Remaining operations: withdrawals, investments, settings, summaries, and provider evidence.
-- Parameter names are copied into local variables before SQL so column names cannot clash.

create or replace function public.update_own_profile(
  full_name text,
  country_code text,
  phone text,
  email_notifications boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := public.require_user();
  v_name text := btrim(full_name);
  v_country text := upper(btrim(country_code));
  v_phone text := nullif(btrim(coalesce(phone, '')), '');
begin
  if char_length(v_name) < 2 then
    raise exception 'Enter your full legal name.';
  end if;
  if v_country !~ '^[A-Z]{2}$' then
    raise exception 'Choose your country of residence.';
  end if;
  if v_phone is not null and v_phone !~ '^\+?[0-9 ()-]{7,32}$' then
    raise exception 'Enter a valid phone number or leave it blank.';
  end if;

  update public.profiles
    set full_name = left(v_name, 120),
        country_code = v_country,
        phone = v_phone,
        notification_preferences = jsonb_build_object('email', email_notifications, 'in_app', true)
  where id = uid;
end;
$$;

create or replace function public.create_deposit_request(
  amount_cents bigint,
  asset_id uuid,
  idempotency_key uuid,
  risk_acknowledged boolean
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := public.require_user();
  v_amount bigint := amount_cents;
  v_asset_id uuid := asset_id;
  v_key uuid := idempotency_key;
  asset public.deposit_assets;
  existing_id uuid;
  new_id uuid;
  ref text;
  deposits_open boolean;
begin
  perform public.consume_rate_limit('deposit:' || uid::text, 8, 3600);
  if risk_acknowledged is distinct from true then
    raise exception 'Confirm that you understand a cryptocurrency transfer can be irreversible.';
  end if;
  if v_amount is null or v_amount <= 0 then
    raise exception 'Enter a deposit amount greater than zero.';
  end if;
  if not public.client_can_fund(uid) then
    raise exception 'Funding opens after your email is verified and your account is approved.';
  end if;

  select deposits_enabled into deposits_open from public.app_settings where id = 1;
  if deposits_open is distinct from true then
    raise exception 'Deposits are not currently open.';
  end if;

  select * into asset from public.deposit_assets where id = v_asset_id for update;
  if asset.id is null or asset.deposit_enabled is distinct from true then
    raise exception 'That asset and network is not available for deposits.';
  end if;
  if v_amount < asset.minimum_deposit_cents or v_amount > asset.maximum_deposit_cents then
    raise exception 'The amount is outside the configured minimum and maximum for this asset.';
  end if;

  select id into existing_id
  from public.deposit_requests
  where user_id = uid and deposit_requests.idempotency_key = v_key;
  if existing_id is not null then
    return existing_id;
  end if;

  ref := public.make_reference('DEP');
  insert into public.deposit_requests (
    reference, user_id, requested_amount_cents, asset_id,
    asset_symbol_snapshot, asset_name_snapshot, network_name_snapshot,
    network_identifier_snapshot, asset_contract_snapshot,
    receiving_address_display, address_is_shared_snapshot,
    status, idempotency_key, risk_acknowledged_at, submitted_at
  ) values (
    ref, uid, v_amount, asset.id,
    asset.symbol, asset.asset_name, asset.network_name,
    asset.network_identifier, asset.asset_contract,
    asset.receiving_address, asset.address_is_shared,
    'awaiting_payment', v_key, now(), now()
  ) returning id into new_id;

  perform public.write_audit(uid, 'deposit_created', 'deposit_request', new_id, null,
    jsonb_build_object('reference', ref, 'amount_cents', v_amount, 'asset', asset.symbol, 'network', asset.network_identifier));
  perform public.notify_admins(
    'deposit_created', 'New deposit request',
    'A client created deposit ' || ref || '.',
    'deposit_request', new_id,
    'New Aztek deposit request',
    'A deposit request is waiting for payment. Review it in the admin dashboard. This email does not include a wallet address.'
  );
  perform public.notify_user(
    uid, 'deposit_created', 'Deposit request created',
    'Your deposit request ' || ref || ' was created. Your account will be credited only after the payment is verified.',
    'deposit_request', new_id,
    'Your Aztek deposit request was created',
    'Your deposit request was created. Sign in to view payment instructions. Your account is not credited until the payment is verified.'
  );
  return new_id;
end;
$$;

create or replace function public.release_withdrawal_reservation(target_withdrawal uuid, actor uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  request public.withdrawal_requests;
  tx_id uuid;
  cash_account uuid;
  reserved_account uuid;
begin
  select * into request from public.withdrawal_requests where id = target_withdrawal for update;
  if request.reserved_ledger_transaction_id is null then
    return;
  end if;
  if exists (
    select 1 from public.ledger_transactions
    where idempotency_key = 'withdrawal-release:' || request.id::text
  ) then
    return;
  end if;

  cash_account := public.lock_client_account(request.user_id, 'client_cash');
  reserved_account := public.lock_client_account(request.user_id, 'client_cash_reserved');
  tx_id := public.begin_ledger(
    'withdrawal_release', 'withdrawal_request', request.id,
    'Withdrawal reservation released ' || request.reference,
    'withdrawal-release:' || request.id::text,
    actor
  );
  if tx_id is null then
    return;
  end if;
  perform public.add_ledger_leg(tx_id, reserved_account, request.requested_amount_cents, 0);
  perform public.add_ledger_leg(tx_id, cash_account, 0, request.requested_amount_cents);
end;
$$;

create or replace function public.request_withdrawal(
  amount_cents bigint,
  asset_id uuid,
  destination_address text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := public.require_user();
  v_amount bigint := amount_cents;
  v_asset_id uuid := asset_id;
  asset public.deposit_assets;
  address text;
  cash_account uuid;
  reserved_account uuid;
  available bigint;
  new_id uuid;
  ref text;
  tx_id uuid;
  payout bigint;
  withdrawals_open boolean;
begin
  perform public.consume_rate_limit('withdrawal:' || uid::text, 6, 3600);
  if not public.client_can_fund(uid) then
    raise exception 'Withdrawals open after your account is approved.';
  end if;
  select withdrawals_enabled into withdrawals_open from public.app_settings where id = 1;
  if withdrawals_open is distinct from true then
    raise exception 'Withdrawals are not currently open.';
  end if;
  if v_amount is null or v_amount <= 0 then
    raise exception 'Enter a withdrawal amount greater than zero.';
  end if;

  select * into asset from public.deposit_assets where id = v_asset_id;
  if asset.id is null or asset.withdrawal_enabled is distinct from true then
    raise exception 'That asset and network is not available for withdrawals.';
  end if;
  address := public.assert_destination_address(destination_address);
  if asset.withdrawal_fee_cents is null or v_amount <= asset.withdrawal_fee_cents then
    raise exception 'The requested amount must be greater than the configured fee.';
  end if;
  payout := v_amount - asset.withdrawal_fee_cents;

  cash_account := public.lock_client_account(uid, 'client_cash');
  reserved_account := public.lock_client_account(uid, 'client_cash_reserved');
  available := public.liability_balance(cash_account);
  if v_amount > available then
    raise exception 'The amount exceeds your available withdrawal balance.';
  end if;

  ref := public.make_reference('WDR');
  insert into public.withdrawal_requests (
    reference, user_id, requested_amount_cents, asset_id, asset_symbol_snapshot,
    network_name_snapshot, destination_address, network_identifier,
    fee_amount_cents, payout_amount_cents, status
  ) values (
    ref, uid, v_amount, asset.id, asset.symbol, asset.network_name, address,
    asset.network_identifier, asset.withdrawal_fee_cents, payout, 'requested'
  ) returning id into new_id;

  tx_id := public.begin_ledger(
    'withdrawal_reserve', 'withdrawal_request', new_id,
    'Withdrawal reserved ' || ref,
    'withdrawal-reserve:' || new_id::text,
    uid
  );
  perform public.add_ledger_leg(tx_id, cash_account, v_amount, 0);
  perform public.add_ledger_leg(tx_id, reserved_account, 0, v_amount);
  update public.withdrawal_requests
    set reserved_ledger_transaction_id = tx_id
  where id = new_id;

  perform public.write_audit(uid, 'withdrawal_requested', 'withdrawal_request', new_id, null,
    jsonb_build_object('reference', ref, 'amount_cents', v_amount));
  perform public.notify_admins(
    'withdrawal_requested', 'Withdrawal request',
    'Withdrawal ' || ref || ' is waiting for review.',
    'withdrawal_request', new_id,
    'New Aztek withdrawal request',
    'A withdrawal request is waiting for review. This email does not include a destination address.'
  );
  perform public.notify_user(
    uid, 'withdrawal_requested', 'Withdrawal request submitted',
    'Your withdrawal request ' || ref || ' has been submitted for review. The amount has been reserved and is not available for another request.',
    'withdrawal_request', new_id,
    'Your Aztek withdrawal request was submitted',
    'Your withdrawal request was submitted for review. Sign in to follow its status.'
  );
  return new_id;
end;
$$;

create or replace function public.cancel_withdrawal(withdrawal_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := public.require_user();
  request public.withdrawal_requests;
begin
  select * into request
  from public.withdrawal_requests
  where id = cancel_withdrawal.withdrawal_id
  for update;
  if request.id is null or request.user_id <> uid then
    raise exception 'Withdrawal request was not found.';
  end if;
  if request.status not in ('requested', 'under_review') then
    raise exception 'This withdrawal can no longer be cancelled.';
  end if;

  perform public.release_withdrawal_reservation(request.id, uid);
  update public.withdrawal_requests
    set status = 'cancelled'
  where id = request.id;
  perform public.write_audit(uid, 'withdrawal_cancelled', 'withdrawal_request', request.id, null, '{}'::jsonb);
end;
$$;

create or replace function public.review_withdrawal(
  withdrawal_id uuid,
  decision text,
  reason text,
  payout_transaction_hash text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := public.require_user();
  request public.withdrawal_requests;
  note text := btrim(coalesce(reason, ''));
  tx_id uuid;
  reserved_account uuid;
  custody_account uuid;
  fee_account uuid;
  payout_hash text;
begin
  if not public.is_admin() then
    raise exception 'You do not have permission to review withdrawals.';
  end if;
  if decision not in ('review', 'approve', 'reject', 'processing', 'complete', 'fail') then
    raise exception 'Choose a valid withdrawal decision.';
  end if;
  if char_length(note) < 8 then
    raise exception 'Enter a reason for this withdrawal decision.';
  end if;

  select * into request from public.withdrawal_requests where id = review_withdrawal.withdrawal_id for update;
  if request.id is null then
    raise exception 'Withdrawal request was not found.';
  end if;
  if request.status = 'completed' then
    raise exception 'A completed withdrawal cannot be changed.';
  end if;

  if decision = 'review' and request.status = 'requested' then
    update public.withdrawal_requests
      set status = 'under_review', reviewed_by = actor, review_reason = note
    where id = request.id;
  elsif decision = 'approve' and request.status in ('requested', 'under_review') then
    update public.withdrawal_requests
      set status = 'approved', reviewed_by = actor, review_reason = note
    where id = request.id;
  elsif decision = 'processing' and request.status = 'approved' then
    update public.withdrawal_requests
      set status = 'processing', reviewed_by = actor, review_reason = note
    where id = request.id;
  elsif decision = 'reject' and request.status in ('requested', 'under_review', 'approved') then
    perform public.release_withdrawal_reservation(request.id, actor);
    update public.withdrawal_requests
      set status = 'rejected', reviewed_by = actor, review_reason = note, processed_at = now()
    where id = request.id;
  elsif decision = 'fail' and request.status in ('approved', 'processing') then
    perform public.release_withdrawal_reservation(request.id, actor);
    update public.withdrawal_requests
      set status = 'failed', reviewed_by = actor, review_reason = note, processed_at = now()
    where id = request.id;
  elsif decision = 'complete' and request.status in ('approved', 'processing') then
    payout_hash := public.assert_tx_hash(coalesce(payout_transaction_hash, ''));
    if exists (
      select 1 from public.ledger_transactions
      where idempotency_key = 'withdrawal-complete:' || request.id::text
    ) then
      update public.withdrawal_requests
        set status = 'completed', payout_transaction_hash = payout_hash,
            reviewed_by = actor, review_reason = note, processed_at = coalesce(processed_at, now())
      where id = request.id;
    else
      reserved_account := public.lock_client_account(request.user_id, 'client_cash_reserved');
      custody_account := public.company_account('company_custody_cash');
      fee_account := public.company_account('company_fee_revenue');
      tx_id := public.begin_ledger(
        'withdrawal_complete', 'withdrawal_request', request.id,
        'Withdrawal completed ' || request.reference,
        'withdrawal-complete:' || request.id::text,
        actor
      );
      perform public.add_ledger_leg(tx_id, reserved_account, request.requested_amount_cents, 0);
      perform public.add_ledger_leg(tx_id, custody_account, 0, request.payout_amount_cents);
      if request.fee_amount_cents > 0 then
        perform public.add_ledger_leg(tx_id, fee_account, 0, request.fee_amount_cents);
      end if;
      update public.withdrawal_requests
        set status = 'completed', payout_transaction_hash = payout_hash,
            reviewed_by = actor, review_reason = note, processed_at = now()
      where id = request.id;
    end if;
  else
    raise exception 'That decision does not match the current withdrawal status.';
  end if;

  perform public.write_audit(actor, 'withdrawal_' || decision, 'withdrawal_request', request.id, note, '{}'::jsonb);
  perform public.notify_user(
    request.user_id, 'withdrawal_status_changed', 'Withdrawal status updated',
    'Withdrawal ' || request.reference || ' is now ' || replace(decision, '_', ' ') || '.',
    'withdrawal_request', request.id,
    'Your Aztek withdrawal status was updated',
    'Sign in to view the latest status of your withdrawal request.'
  );
end;
$$;

create or replace function public.record_investment_allocation(
  target_user uuid,
  category public.investment_category,
  description text,
  amount_cents bigint,
  execution_reference text,
  evidence_reference text,
  executed_at timestamptz
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := public.require_user();
  v_amount bigint := amount_cents;
  v_description text := btrim(description);
  v_execution text := btrim(execution_reference);
  v_evidence text := btrim(evidence_reference);
  cash_account uuid;
  invested_account uuid;
  available bigint;
  record_id uuid;
  holding_id uuid;
  tx_id uuid;
  ref text;
begin
  if not public.can_manage_investments() then
    raise exception 'You do not have permission to record investments.';
  end if;
  if v_amount is null or v_amount <= 0 then
    raise exception 'Enter an allocation amount greater than zero.';
  end if;
  if char_length(v_description) < 8 or char_length(v_execution) < 3 or char_length(v_evidence) < 3 then
    raise exception 'Description, execution reference, and evidence reference are required.';
  end if;
  if not exists (select 1 from public.profiles where id = target_user and role = 'client') then
    raise exception 'Choose a client account.';
  end if;

  cash_account := public.lock_client_account(target_user, 'client_cash');
  invested_account := public.lock_client_account(target_user, 'client_investments');
  available := public.liability_balance(cash_account);
  if v_amount > available then
    raise exception 'The allocation exceeds the client confirmed cash balance.';
  end if;

  ref := public.make_reference('INV');
  insert into public.investment_records (
    user_id, activity_reference, category, description, execution_reference,
    amount_allocated_cents, executed_at, recorded_by, evidence_reference, status
  ) values (
    target_user, ref, category, v_description, v_execution,
    v_amount, executed_at, actor, v_evidence, 'open'
  ) returning id into record_id;

  insert into public.portfolio_holdings (
    user_id, investment_record_id, category, cost_basis_cents, current_valuation_cents,
    valuation_timestamp, valuation_source, status
  ) values (
    target_user, record_id, category, v_amount, v_amount, coalesce(executed_at, now()),
    'allocation_at_cost', 'active'
  ) returning id into holding_id;

  tx_id := public.begin_ledger(
    'investment_allocation', 'investment_record', record_id,
    'Allocated to managed investment ' || ref,
    'allocation:' || record_id::text,
    actor
  );
  perform public.add_ledger_leg(tx_id, cash_account, v_amount, 0);
  perform public.add_ledger_leg(tx_id, invested_account, 0, v_amount);
  perform public.add_ledger_leg(tx_id, public.company_account('company_custody_cash'), 0, v_amount);
  perform public.add_ledger_leg(tx_id, public.company_account('company_invested_assets'), v_amount, 0);
  perform public.record_valuation_snapshot(target_user, 'allocation_at_cost', actor);
  perform public.write_audit(actor, 'investment_allocated', 'investment_record', record_id, v_evidence,
    jsonb_build_object('amount_cents', v_amount, 'holding_id', holding_id));
  perform public.notify_user(
    target_user, 'investment_record_updated', 'Managed investment recorded',
    'An allocation was recorded on your account as ' || ref || '. This is not a deposit and it does not by itself create a gain.',
    'investment_record', record_id,
    'Your Aztek portfolio was updated',
    'A managed investment record was added to your account. Sign in to review it.'
  );
  return record_id;
end;
$$;

create or replace function public.record_holding_valuation(
  holding_id uuid,
  current_valuation_cents bigint,
  evidence_reference text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := public.require_user();
  holding public.portfolio_holdings;
  v_value bigint := current_valuation_cents;
  v_evidence text := btrim(evidence_reference);
begin
  if not public.can_manage_investments() then
    raise exception 'You do not have permission to record valuations.';
  end if;
  if v_value is null or v_value < 0 or char_length(v_evidence) < 3 then
    raise exception 'Enter a valuation and an evidence reference.';
  end if;

  select * into holding from public.portfolio_holdings where id = record_holding_valuation.holding_id for update;
  if holding.id is null or holding.status <> 'active' then
    raise exception 'Active holding was not found.';
  end if;

  update public.portfolio_holdings
    set current_valuation_cents = v_value,
        valuation_timestamp = now(),
        valuation_source = 'verified_valuation'
  where id = holding.id;

  perform public.record_valuation_snapshot(holding.user_id, 'verified_valuation', actor);
  perform public.write_audit(actor, 'valuation_recorded', 'portfolio_holding', holding.id, v_evidence,
    jsonb_build_object('valuation_cents', v_value));
  perform public.notify_user(
    holding.user_id, 'investment_record_updated', 'Portfolio valuation recorded',
    'A verified valuation was recorded on your managed portfolio.',
    'portfolio_holding', holding.id,
    'Your Aztek portfolio valuation was updated',
    'Sign in to view the latest valuation recorded on your account.'
  );
end;
$$;

create or replace function public.close_investment_holding(
  holding_id uuid,
  proceeds_cents bigint,
  execution_reference text,
  evidence_reference text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := public.require_user();
  holding public.portfolio_holdings;
  v_proceeds bigint := proceeds_cents;
  v_execution text := btrim(execution_reference);
  v_evidence text := btrim(evidence_reference);
  tx_id uuid;
  realized bigint;
begin
  if not public.can_manage_investments() then
    raise exception 'You do not have permission to close investments.';
  end if;
  if v_proceeds is null or v_proceeds < 0 or char_length(v_execution) < 3 or char_length(v_evidence) < 3 then
    raise exception 'Enter proceeds, an execution reference, and an evidence reference.';
  end if;

  select * into holding from public.portfolio_holdings where id = close_investment_holding.holding_id for update;
  if holding.id is null or holding.status <> 'active' then
    raise exception 'Active holding was not found.';
  end if;
  if holding.cost_basis_cents is null then
    raise exception 'This holding has no cost basis to close.';
  end if;

  realized := v_proceeds - holding.cost_basis_cents;
  perform public.lock_client_account(holding.user_id, 'client_cash');
  perform public.lock_client_account(holding.user_id, 'client_investments');
  tx_id := public.begin_ledger(
    'investment_close', 'portfolio_holding', holding.id,
    'Investment proceeds recorded',
    'close:' || holding.id::text,
    actor
  );
  perform public.add_ledger_leg(tx_id, public.lock_client_account(holding.user_id, 'client_investments'), holding.cost_basis_cents, 0);
  perform public.add_ledger_leg(tx_id, public.company_account('company_invested_assets'), 0, holding.cost_basis_cents);
  if v_proceeds > 0 then
    perform public.add_ledger_leg(tx_id, public.company_account('company_custody_cash'), v_proceeds, 0);
    perform public.add_ledger_leg(tx_id, public.lock_client_account(holding.user_id, 'client_cash'), 0, v_proceeds);
  end if;

  update public.portfolio_holdings
    set status = 'closed',
        current_valuation_cents = 0,
        valuation_source = 'closing',
        valuation_timestamp = now(),
        realized_result_cents = realized
  where id = holding.id;

  update public.investment_records
    set status = 'closed', realized_result_cents = realized, execution_reference = v_execution
  where id = holding.investment_record_id;

  perform public.record_valuation_snapshot(holding.user_id, 'closing', actor);
  perform public.write_audit(actor, 'investment_closed', 'portfolio_holding', holding.id, v_evidence,
    jsonb_build_object('proceeds_cents', v_proceeds, 'realized_cents', realized));
  perform public.notify_user(
    holding.user_id, 'investment_record_updated', 'Managed investment updated',
    'A managed investment was closed and any proceeds were recorded in your account.',
    'portfolio_holding', holding.id,
    'Your Aztek portfolio was updated',
    'Sign in to review a change to your managed investment records.'
  );
end;
$$;

create or replace function public.record_client_fee(
  target_user uuid,
  amount_cents bigint,
  description text,
  evidence_reference text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := public.require_user();
  v_amount bigint := amount_cents;
  v_description text := btrim(description);
  v_evidence text := btrim(evidence_reference);
  cash_account uuid;
  tx_id uuid;
begin
  if not public.can_manage_investments() and not public.is_admin() then
    raise exception 'You do not have permission to record fees.';
  end if;
  if v_amount is null or v_amount <= 0 or char_length(v_description) < 8 or char_length(v_evidence) < 3 then
    raise exception 'Enter a fee amount, description, and evidence reference.';
  end if;
  cash_account := public.lock_client_account(target_user, 'client_cash');
  if v_amount > public.liability_balance(cash_account) then
    raise exception 'The fee exceeds confirmed cash. Reserved and invested funds are not charged by this action.';
  end if;
  tx_id := public.begin_ledger(
    'fee', 'profile', target_user, v_description,
    'fee:' || gen_random_uuid()::text, actor
  );
  perform public.add_ledger_leg(tx_id, cash_account, v_amount, 0);
  perform public.add_ledger_leg(tx_id, public.company_account('company_fee_revenue'), 0, v_amount);
  perform public.record_valuation_snapshot(target_user, 'fee', actor);
  perform public.write_audit(actor, 'fee_recorded', 'profile', target_user, v_evidence,
    jsonb_build_object('amount_cents', v_amount, 'ledger_transaction_id', tx_id));
  perform public.notify_user(
    target_user, 'account_notice', 'Fee recorded',
    v_description, 'profile', target_user,
    'A fee was recorded on your Aztek account',
    'Sign in to review the fee recorded on your account.'
  );
end;
$$;

create or replace function public.adjust_client_cash(
  target_user uuid,
  direction text,
  amount_cents bigint,
  description text,
  reason text,
  evidence_reference text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := public.require_user();
  v_amount bigint := amount_cents;
  v_description text := btrim(description);
  v_reason text := btrim(reason);
  v_evidence text := btrim(evidence_reference);
  cash_account uuid;
  tx_id uuid;
begin
  if not public.is_admin() then
    raise exception 'You do not have permission to post adjustments.';
  end if;
  if direction not in ('credit', 'debit') then
    raise exception 'Choose whether the adjustment credits or debits client cash.';
  end if;
  if v_amount is null or v_amount <= 0
     or char_length(v_description) < 8
     or char_length(v_reason) < 10
     or char_length(v_evidence) < 3 then
    raise exception 'Amount, client-facing description, internal reason, and evidence are required.';
  end if;

  cash_account := public.lock_client_account(target_user, 'client_cash');
  if direction = 'debit' and v_amount > public.liability_balance(cash_account) then
    raise exception 'The debit exceeds confirmed cash.';
  end if;

  tx_id := public.begin_ledger(
    'adjustment', 'profile', target_user, v_description,
    'adjustment:' || gen_random_uuid()::text, actor
  );
  if direction = 'credit' then
    perform public.add_ledger_leg(tx_id, public.company_account('company_custody_cash'), v_amount, 0);
    perform public.add_ledger_leg(tx_id, cash_account, 0, v_amount);
  else
    perform public.add_ledger_leg(tx_id, cash_account, v_amount, 0);
    perform public.add_ledger_leg(tx_id, public.company_account('company_custody_cash'), 0, v_amount);
  end if;

  perform public.write_audit(actor, 'cash_adjusted', 'profile', target_user, v_reason,
    jsonb_build_object('direction', direction, 'amount_cents', v_amount, 'evidence', v_evidence, 'ledger_transaction_id', tx_id));
  perform public.notify_user(
    target_user, 'account_notice', 'Account adjustment recorded',
    v_description, 'profile', target_user,
    'Your Aztek account was adjusted',
    'Sign in to review an adjustment recorded on your account.'
  );
end;
$$;

create or replace function public.upsert_deposit_asset(
  asset_id uuid,
  symbol text,
  asset_name text,
  network_name text,
  network_identifier text,
  asset_contract text,
  receiving_address text,
  address_is_shared boolean,
  address_verified boolean,
  minimum_deposit_cents bigint,
  maximum_deposit_cents bigint,
  required_confirmations integer,
  deposit_enabled boolean,
  withdrawal_enabled boolean,
  withdrawal_fee_cents bigint,
  custody_provider text,
  decimals integer
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := public.require_user();
  v_id uuid := asset_id;
  v_symbol text := upper(btrim(symbol));
  v_address text := nullif(btrim(coalesce(receiving_address, '')), '');
  v_verified_at timestamptz;
begin
  if not public.is_admin() then
    raise exception 'You do not have permission to configure wallets.';
  end if;
  if v_symbol !~ '^[A-Z0-9]{2,12}$' or char_length(btrim(asset_name)) < 2 then
    raise exception 'Enter a valid asset symbol and name.';
  end if;
  if char_length(btrim(network_name)) < 2 or char_length(btrim(network_identifier)) < 2 then
    raise exception 'Enter the network name and network identifier.';
  end if;
  if v_address is not null then
    v_address := public.assert_destination_address(v_address);
  end if;
  if coalesce(address_verified, false) and v_address is not null then
    v_verified_at := now();
  else
    v_verified_at := null;
  end if;
  if coalesce(deposit_enabled, false) and (v_address is null or v_verified_at is null) then
    raise exception 'Verify a receiving address before enabling deposits.';
  end if;
  if coalesce(withdrawal_enabled, false) and (v_address is null or withdrawal_fee_cents is null) then
    raise exception 'A verified address and fee are required before enabling withdrawals.';
  end if;

  if v_id is null then
    insert into public.deposit_assets (
      symbol, asset_name, network_name, network_identifier, asset_contract,
      receiving_address, address_is_shared, address_verified_at,
      minimum_deposit_cents, maximum_deposit_cents, required_confirmations,
      deposit_enabled, withdrawal_enabled, withdrawal_fee_cents, custody_provider, decimals
    ) values (
      v_symbol, btrim(asset_name), btrim(network_name), btrim(network_identifier),
      nullif(btrim(coalesce(asset_contract, '')), ''),
      v_address, coalesce(address_is_shared, true), v_verified_at,
      coalesce(minimum_deposit_cents, 0), maximum_deposit_cents, coalesce(required_confirmations, 12),
      coalesce(deposit_enabled, false), coalesce(withdrawal_enabled, false),
      withdrawal_fee_cents, nullif(btrim(coalesce(custody_provider, '')), ''), coalesce(decimals, 6)
    ) returning id into v_id;
  else
    update public.deposit_assets
      set symbol = v_symbol,
          asset_name = btrim(asset_name),
          network_name = btrim(network_name),
          network_identifier = btrim(network_identifier),
          asset_contract = nullif(btrim(coalesce(asset_contract, '')), ''),
          receiving_address = v_address,
          address_is_shared = coalesce(address_is_shared, true),
          address_verified_at = v_verified_at,
          minimum_deposit_cents = coalesce(minimum_deposit_cents, 0),
          maximum_deposit_cents = upsert_deposit_asset.maximum_deposit_cents,
          required_confirmations = coalesce(required_confirmations, 12),
          deposit_enabled = coalesce(upsert_deposit_asset.deposit_enabled, false),
          withdrawal_enabled = coalesce(upsert_deposit_asset.withdrawal_enabled, false),
          withdrawal_fee_cents = upsert_deposit_asset.withdrawal_fee_cents,
          custody_provider = nullif(btrim(coalesce(custody_provider, '')), ''),
          decimals = coalesce(decimals, 6)
    where id = v_id;
    if not found then
      raise exception 'Asset configuration was not found.';
    end if;
  end if;

  perform public.write_audit(actor, 'deposit_asset_saved', 'deposit_asset', v_id,
    case when v_verified_at is null then 'Saved without a verified address' else 'Receiving address marked verified' end,
    jsonb_build_object('symbol', v_symbol, 'network', btrim(network_identifier), 'deposit_enabled', deposit_enabled));
  return v_id;
end;
$$;

create or replace function public.update_app_settings(
  deposits_enabled boolean,
  withdrawals_enabled boolean,
  support_email text,
  deposit_notification_email text,
  withdrawal_processing_notice text,
  deposit_expiry_hours integer
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := public.require_user();
  v_support text := nullif(btrim(coalesce(support_email, '')), '');
  v_notice text := nullif(btrim(coalesce(deposit_notification_email, '')), '');
  v_copy text := btrim(withdrawal_processing_notice);
begin
  if not public.is_admin() then
    raise exception 'You do not have permission to change application settings.';
  end if;
  if v_support is not null and v_support !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid support email or leave it blank.';
  end if;
  if v_notice is not null and v_notice !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid deposit notification email or leave it blank.';
  end if;
  if char_length(v_copy) < 20 then
    raise exception 'Enter the withdrawal processing notice clients will see.';
  end if;
  if deposit_expiry_hours < 1 or deposit_expiry_hours > 720 then
    raise exception 'Deposit expiry must be between 1 and 720 hours.';
  end if;

  update public.app_settings
    set deposits_enabled = update_app_settings.deposits_enabled,
        withdrawals_enabled = update_app_settings.withdrawals_enabled,
        support_email = v_support,
        deposit_notification_email = v_notice,
        withdrawal_processing_notice = v_copy,
        deposit_expiry_hours = update_app_settings.deposit_expiry_hours,
        updated_by = actor
  where id = 1;

  perform public.write_audit(actor, 'settings_updated', 'app_settings', null, null,
    jsonb_build_object('deposits_enabled', deposits_enabled, 'withdrawals_enabled', withdrawals_enabled));
end;
$$;

create or replace function public.send_account_notice(
  target_user uuid,
  title text,
  message text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := public.require_user();
  v_title text := btrim(title);
  v_message text := btrim(message);
begin
  if not public.can_support() then
    raise exception 'You do not have permission to send notices.';
  end if;
  if char_length(v_title) < 3 or char_length(v_message) < 8 then
    raise exception 'Enter a title and message.';
  end if;
  perform public.notify_user(
    target_user, 'account_notice', left(v_title, 120), left(v_message, 2000),
    'profile', target_user, 'A notice from Aztek',
    'Sign in to your Aztek account to read a new notice.'
  );
  perform public.write_audit(actor, 'notice_sent', 'profile', target_user, v_title, '{}'::jsonb);
end;
$$;

create or replace function public.mark_notifications_read(notification_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := public.require_user();
begin
  update public.notifications
    set read_at = now()
  where user_id = uid
    and read_at is null
    and (mark_notifications_read.notification_id is null or id = mark_notifications_read.notification_id);
end;
$$;

create or replace function public.create_support_conversation(subject text, message text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := public.require_user();
  v_subject text := btrim(subject);
  v_message text := btrim(message);
  conversation_id uuid;
begin
  perform public.consume_rate_limit('support:' || uid::text, 10, 3600);
  if char_length(v_subject) < 3 or char_length(v_message) < 1 then
    raise exception 'Enter a subject and message.';
  end if;
  insert into public.support_conversations (user_id, subject)
  values (uid, left(v_subject, 160))
  returning id into conversation_id;
  insert into public.support_messages (conversation_id, sender_user_id, message)
  values (conversation_id, uid, left(v_message, 4000));
  perform public.notify_admins(
    'account_notice', 'Support request',
    'A client opened a support conversation.',
    'support_conversation', conversation_id,
    'New Aztek support request',
    'A client opened a support conversation. Sign in to reply.'
  );
  return conversation_id;
end;
$$;

create or replace function public.reply_support_message(conversation_id uuid, message text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := public.require_user();
  owner uuid;
  v_message text := btrim(message);
begin
  if char_length(v_message) < 1 then
    raise exception 'Enter a message.';
  end if;
  select user_id into owner from public.support_conversations where id = reply_support_message.conversation_id;
  if owner is null then
    raise exception 'Conversation was not found.';
  end if;
  if owner <> uid and not public.can_support() then
    raise exception 'You do not have permission to reply to this conversation.';
  end if;

  insert into public.support_messages (conversation_id, sender_user_id, message)
  values (reply_support_message.conversation_id, uid, left(v_message, 4000));
  update public.support_conversations
    set status = case when owner = uid then 'open'::public.support_status else 'pending'::public.support_status end
  where id = reply_support_message.conversation_id;

  if owner <> uid then
    perform public.notify_user(
      owner, 'support_reply', 'Support reply',
      'The Aztek team replied to your support conversation.',
      'support_conversation', reply_support_message.conversation_id,
      'You have a reply from Aztek',
      'Sign in to read the reply to your support conversation.'
    );
  end if;
end;
$$;

create or replace function public.submit_contact_inquiry(
  full_name text,
  email text,
  message text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := btrim(full_name);
  v_email text := lower(btrim(email));
  v_message text := btrim(message);
begin
  perform public.consume_rate_limit('contact:' || v_email, 5, 3600);
  if char_length(v_name) < 2 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_message) < 10 then
    raise exception 'Enter your name, a valid email, and a message.';
  end if;
  insert into public.contact_inquiries (user_id, full_name, email, message)
  values (auth.uid(), left(v_name, 120), v_email, left(v_message, 4000));
end;
$$;

create or replace function public.get_account_summary(target_user uuid)
returns table (
  cash_cents bigint,
  reserved_cents bigint,
  invested_cost_cents bigint,
  holdings_value_cents bigint,
  active_holdings integer,
  unvalued_holdings integer,
  total_account_value_cents bigint,
  valuation_complete boolean,
  confirmed_deposits_cents bigint,
  pending_deposits_cents bigint,
  completed_withdrawals_cents bigint,
  fees_cents bigint,
  realized_pnl_cents bigint,
  has_verified_valuation boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user uuid := target_user;
begin
  if auth.uid() is distinct from v_user and not public.can_view_ledger() then
    raise exception 'You do not have permission to view this account.';
  end if;

  return query
  select
    public.liability_balance(a_cash.id),
    public.liability_balance(a_reserved.id),
    public.liability_balance(a_invested.id),
    coalesce((
      select sum(h.current_valuation_cents)::bigint
      from public.portfolio_holdings h
      where h.user_id = v_user and h.status = 'active' and h.current_valuation_cents is not null
    ), 0)::bigint,
    coalesce((
      select count(*)::integer from public.portfolio_holdings h
      where h.user_id = v_user and h.status = 'active'
    ), 0),
    coalesce((
      select count(*)::integer from public.portfolio_holdings h
      where h.user_id = v_user and h.status = 'active' and h.current_valuation_cents is null
    ), 0),
    (
      public.liability_balance(a_cash.id)
      + public.liability_balance(a_reserved.id)
      + coalesce((
          select sum(h.current_valuation_cents)::bigint
          from public.portfolio_holdings h
          where h.user_id = v_user and h.status = 'active' and h.current_valuation_cents is not null
        ), 0)
    )::bigint,
    not exists (
      select 1 from public.portfolio_holdings h
      where h.user_id = v_user and h.status = 'active' and h.current_valuation_cents is null
    ),
    coalesce((
      select sum(d.credited_amount_cents)::bigint
      from public.deposit_requests d
      where d.user_id = v_user and d.status = 'credited'
    ), 0)::bigint,
    coalesce((
      select sum(d.requested_amount_cents)::bigint
      from public.deposit_requests d
      where d.user_id = v_user
        and d.status in ('awaiting_payment', 'payment_detected', 'confirming', 'under_review')
    ), 0)::bigint,
    coalesce((
      select sum(w.requested_amount_cents)::bigint
      from public.withdrawal_requests w
      where w.user_id = v_user and w.status = 'completed'
    ), 0)::bigint,
    coalesce((
      select sum(le.debit_amount)::bigint
      from public.ledger_entries le
      join public.ledger_transactions lt on lt.id = le.ledger_transaction_id
      where le.account_id = a_cash.id and lt.transaction_type = 'fee'
    ), 0)::bigint,
    coalesce((
      select sum(h.realized_result_cents)::bigint
      from public.portfolio_holdings h
      where h.user_id = v_user and h.realized_result_cents is not null
    ), 0)::bigint,
    exists (
      select 1 from public.portfolio_valuations v
      where v.user_id = v_user and v.valuation_source in ('verified_valuation', 'closing')
    )
  from public.account_ledger_accounts a_cash
  join public.account_ledger_accounts a_reserved
    on a_reserved.account_owner_user_id = v_user and a_reserved.account_type = 'client_cash_reserved'
  join public.account_ledger_accounts a_invested
    on a_invested.account_owner_user_id = v_user and a_invested.account_type = 'client_investments'
  where a_cash.account_owner_user_id = v_user and a_cash.account_type = 'client_cash';
end;
$$;

create or replace function public.get_admin_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception 'You do not have permission to view the operations overview.';
  end if;
  return jsonb_build_object(
    'clients', (select count(*) from public.profiles where role = 'client'),
    'awaiting_verification', (select count(*) from public.profiles where role = 'client' and verification_status = 'pending_review'),
    'pending_deposits', (select count(*) from public.deposit_requests where status in ('awaiting_payment', 'payment_detected', 'confirming', 'under_review')),
    'deposits_under_review', (select count(*) from public.deposit_requests where status = 'under_review'),
    'pending_withdrawals', (select count(*) from public.withdrawal_requests where status in ('requested', 'under_review', 'approved', 'processing')),
    'open_support', (select count(*) from public.support_conversations where status in ('open', 'pending'))
  );
end;
$$;

create or replace function public.get_ledger_reconciliation()
returns table (
  custody_cash_cents bigint,
  invested_assets_cents bigint,
  client_liabilities_cents bigint,
  fee_revenue_cents bigint,
  break_cents bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  assets bigint;
  liabilities bigint;
  fees bigint;
begin
  if not public.can_manage_investments() and not public.is_admin() then
    raise exception 'You do not have permission to reconcile the ledger.';
  end if;
  assets := public.asset_balance(public.company_account('company_custody_cash'))
    + public.asset_balance(public.company_account('company_invested_assets'));
  select coalesce(sum(public.liability_balance(id)), 0)::bigint into liabilities
  from public.account_ledger_accounts
  where account_type in ('client_cash', 'client_cash_reserved', 'client_investments');
  fees := public.liability_balance(public.company_account('company_fee_revenue'));
  return query select
    public.asset_balance(public.company_account('company_custody_cash')),
    public.asset_balance(public.company_account('company_invested_assets')),
    liabilities,
    fees,
    (assets - liabilities - fees);
end;
$$;

create or replace function public.admin_list_deposit_assets()
returns setof public.deposit_assets
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'You do not have permission to view wallet configuration.';
  end if;
  return query select * from public.deposit_assets order by symbol, network_name;
end;
$$;

create or replace function public.record_provider_observation(
  network_identifier text,
  transaction_hash text,
  output_index integer,
  asset_identifier text,
  to_address text,
  raw_amount numeric,
  confirmation_count integer,
  provider_reference text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  observed_id uuid;
  match_id uuid;
  required integer;
  cleaned_hash text := public.assert_tx_hash(transaction_hash);
begin
  if auth.uid() is not null
     and current_user not in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Provider observations must come from the configured integration.';
  end if;
  if current_user not in ('service_role', 'postgres', 'supabase_admin') and not public.is_admin() then
    raise exception 'Provider observations must come from the configured integration.';
  end if;

  insert into public.blockchain_transactions (
    network_identifier, transaction_hash, output_index, asset_identifier,
    to_address, raw_amount, confirmation_count, provider_reference, verification_status
  ) values (
    btrim(network_identifier), cleaned_hash, coalesce(output_index, 0), btrim(asset_identifier),
    btrim(to_address), raw_amount, greatest(coalesce(confirmation_count, 0), 0),
    provider_reference, 'observed'
  )
  on conflict (network_identifier, transaction_hash, output_index)
  do update set
    confirmation_count = greatest(public.blockchain_transactions.confirmation_count, excluded.confirmation_count),
    raw_amount = coalesce(excluded.raw_amount, public.blockchain_transactions.raw_amount),
    last_checked_at = now(),
    provider_reference = coalesce(excluded.provider_reference, public.blockchain_transactions.provider_reference)
  returning id into observed_id;

  select d.id, a.required_confirmations into match_id, required
  from public.deposit_requests d
  join public.deposit_assets a on a.id = d.asset_id
  where d.network_identifier_snapshot = btrim(network_identifier)
    and d.transaction_hash = cleaned_hash
    and d.status in ('awaiting_payment', 'payment_detected', 'confirming', 'under_review')
  for update of d;

  if match_id is null then
    perform public.notify_admins(
      'payment_detected', 'Unmatched payment observed',
      'A blockchain payment was observed and is not attached to a deposit. It was not credited.',
      'blockchain_transaction', observed_id,
      'Unmatched Aztek payment observed',
      'A payment was observed without a matching deposit hash. It was not credited.'
    );
    return observed_id;
  end if;

  update public.blockchain_transactions
    set deposit_id = match_id
  where id = observed_id and deposit_id is null;

  update public.deposit_requests
    set confirmation_count = greatest(coalesce(deposit_requests.confirmation_count, 0), coalesce(record_provider_observation.confirmation_count, 0)),
        observed_crypto_amount = coalesce(raw_amount, observed_crypto_amount),
        observed_address = btrim(to_address),
        status = case
          when coalesce(record_provider_observation.confirmation_count, 0) >= required then 'under_review'::public.deposit_status
          else 'confirming'::public.deposit_status
        end
  where id = match_id;

  perform public.notify_admins(
    'payment_detected', 'Payment observation updated',
    'A monitored payment was updated. An administrator still needs to approve any credit.',
    'deposit_request', match_id,
    'Aztek payment observation updated',
    'A monitored payment was updated. It has not been credited.'
  );
  return observed_id;
end;
$$;


-- ===== 20261014120400_rls.sql =====
-- Deny by default. Clients read their own rows. Mutations go through trusted functions.

create or replace function public.can_view_audit()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('admin', 'compliance')
      and account_status not in ('suspended', 'closed')
  );
$$;

alter table public.profiles enable row level security;
alter table public.profiles force row level security;
alter table public.app_settings enable row level security;
alter table public.app_settings force row level security;
alter table public.deposit_assets enable row level security;
alter table public.deposit_assets force row level security;
alter table public.deposit_requests enable row level security;
alter table public.deposit_requests force row level security;
alter table public.deposit_review_notes enable row level security;
alter table public.deposit_review_notes force row level security;
alter table public.blockchain_transactions enable row level security;
alter table public.blockchain_transactions force row level security;
alter table public.account_ledger_accounts enable row level security;
alter table public.account_ledger_accounts force row level security;
alter table public.ledger_transactions enable row level security;
alter table public.ledger_transactions force row level security;
alter table public.ledger_entries enable row level security;
alter table public.ledger_entries force row level security;
alter table public.investment_records enable row level security;
alter table public.investment_records force row level security;
alter table public.portfolio_holdings enable row level security;
alter table public.portfolio_holdings force row level security;
alter table public.portfolio_valuations enable row level security;
alter table public.portfolio_valuations force row level security;
alter table public.withdrawal_requests enable row level security;
alter table public.withdrawal_requests force row level security;
alter table public.notifications enable row level security;
alter table public.notifications force row level security;
alter table public.notification_outbox enable row level security;
alter table public.notification_outbox force row level security;
alter table public.audit_logs enable row level security;
alter table public.audit_logs force row level security;
alter table public.support_conversations enable row level security;
alter table public.support_conversations force row level security;
alter table public.support_messages enable row level security;
alter table public.support_messages force row level security;
alter table public.contact_inquiries enable row level security;
alter table public.contact_inquiries force row level security;
alter table public.rate_limits enable row level security;
alter table public.rate_limits force row level security;

create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.can_view_clients());

create policy app_settings_select on public.app_settings
  for select to authenticated
  using (public.is_admin());

create policy deposit_assets_select on public.deposit_assets
  for select to authenticated
  using (
    deposit_enabled
    or withdrawal_enabled
    or public.is_admin()
  );

create policy deposit_requests_select on public.deposit_requests
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

create policy deposit_notes_select on public.deposit_review_notes
  for select to authenticated
  using (public.is_admin());

create policy blockchain_select on public.blockchain_transactions
  for select to authenticated
  using (public.is_admin());

create policy ledger_accounts_select on public.account_ledger_accounts
  for select to authenticated
  using (account_owner_user_id = auth.uid() or public.can_view_ledger());

create policy ledger_transactions_select on public.ledger_transactions
  for select to authenticated
  using (
    public.can_view_ledger()
    or exists (
      select 1
      from public.ledger_entries le
      join public.account_ledger_accounts a on a.id = le.account_id
      where le.ledger_transaction_id = ledger_transactions.id
        and a.account_owner_user_id = auth.uid()
    )
  );

create policy ledger_entries_select on public.ledger_entries
  for select to authenticated
  using (
    public.can_view_ledger()
    or exists (
      select 1 from public.account_ledger_accounts a
      where a.id = ledger_entries.account_id
        and a.account_owner_user_id = auth.uid()
    )
  );

create policy investment_records_select on public.investment_records
  for select to authenticated
  using (user_id = auth.uid() or public.can_view_ledger());

create policy holdings_select on public.portfolio_holdings
  for select to authenticated
  using (user_id = auth.uid() or public.can_view_ledger());

create policy valuations_select on public.portfolio_valuations
  for select to authenticated
  using (user_id = auth.uid() or public.can_view_ledger());

create policy withdrawals_select on public.withdrawal_requests
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

create policy notifications_select on public.notifications
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

create policy outbox_select on public.notification_outbox
  for select to authenticated
  using (public.is_admin());

create policy audit_select on public.audit_logs
  for select to authenticated
  using (public.can_view_audit());

create policy support_conversations_select on public.support_conversations
  for select to authenticated
  using (user_id = auth.uid() or public.can_support());

create policy support_messages_select on public.support_messages
  for select to authenticated
  using (
    exists (
      select 1 from public.support_conversations c
      where c.id = support_messages.conversation_id
        and (c.user_id = auth.uid() or public.can_support())
    )
  );

create policy contact_select on public.contact_inquiries
  for select to authenticated
  using (public.can_support());

revoke all on all tables in schema public from public, anon, authenticated;
grant select on public.profiles to authenticated;
grant select (
  id, symbol, asset_name, network_name, network_identifier,
  minimum_deposit_cents, maximum_deposit_cents, required_confirmations,
  deposit_enabled, withdrawal_enabled, withdrawal_fee_cents, decimals, address_is_shared
) on public.deposit_assets to authenticated;
grant select on public.deposit_requests to authenticated;
grant select on public.deposit_review_notes to authenticated;
grant select on public.blockchain_transactions to authenticated;
grant select on public.account_ledger_accounts to authenticated;
grant select on public.ledger_transactions to authenticated;
grant select on public.ledger_entries to authenticated;
grant select on public.investment_records to authenticated;
grant select on public.portfolio_holdings to authenticated;
grant select on public.portfolio_valuations to authenticated;
grant select on public.withdrawal_requests to authenticated;
grant select on public.notifications to authenticated;
grant select on public.notification_outbox to authenticated;
grant select on public.audit_logs to authenticated;
grant select on public.support_conversations to authenticated;
grant select on public.support_messages to authenticated;
grant select on public.contact_inquiries to authenticated;
grant select on public.app_settings to authenticated;

revoke all on all functions in schema public from public, anon, authenticated;

grant execute on function public.actor_role() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_staff() to authenticated;
grant execute on function public.can_view_clients() to authenticated;
grant execute on function public.can_view_ledger() to authenticated;
grant execute on function public.can_review_verification() to authenticated;
grant execute on function public.can_manage_investments() to authenticated;
grant execute on function public.can_support() to authenticated;
grant execute on function public.can_view_audit() to authenticated;
grant execute on function public.get_public_settings() to anon, authenticated;
grant execute on function public.update_own_profile(text, text, text, boolean) to authenticated;
grant execute on function public.acknowledge_welcome() to authenticated;
grant execute on function public.complete_onboarding() to authenticated;
grant execute on function public.request_account_review() to authenticated;
grant execute on function public.admin_set_verification(uuid, public.verification_status, text) to authenticated;
grant execute on function public.admin_set_account_status(uuid, public.account_status, text) to authenticated;
grant execute on function public.expire_my_stale_deposits() to authenticated;
grant execute on function public.create_deposit_request(bigint, uuid, uuid, boolean) to authenticated;
grant execute on function public.submit_deposit_transaction_hash(uuid, text) to authenticated;
grant execute on function public.cancel_deposit_request(uuid) to authenticated;
grant execute on function public.review_deposit(uuid, text, text, bigint, numeric, integer, text) to authenticated;
grant execute on function public.request_withdrawal(bigint, uuid, text) to authenticated;
grant execute on function public.cancel_withdrawal(uuid) to authenticated;
grant execute on function public.review_withdrawal(uuid, text, text, text) to authenticated;
grant execute on function public.record_investment_allocation(uuid, public.investment_category, text, bigint, text, text, timestamptz) to authenticated;
grant execute on function public.record_holding_valuation(uuid, bigint, text) to authenticated;
grant execute on function public.close_investment_holding(uuid, bigint, text, text) to authenticated;
grant execute on function public.record_client_fee(uuid, bigint, text, text) to authenticated;
grant execute on function public.adjust_client_cash(uuid, text, bigint, text, text, text) to authenticated;
grant execute on function public.upsert_deposit_asset(uuid, text, text, text, text, text, text, boolean, boolean, bigint, bigint, integer, boolean, boolean, bigint, text, integer) to authenticated;
grant execute on function public.update_app_settings(boolean, boolean, text, text, text, integer) to authenticated;
grant execute on function public.send_account_notice(uuid, text, text) to authenticated;
grant execute on function public.mark_notifications_read(uuid) to authenticated;
grant execute on function public.create_support_conversation(text, text) to authenticated;
grant execute on function public.reply_support_message(uuid, text) to authenticated;
grant execute on function public.submit_contact_inquiry(text, text, text) to anon, authenticated;
grant execute on function public.get_account_summary(uuid) to authenticated;
grant execute on function public.get_admin_overview() to authenticated;
grant execute on function public.get_ledger_reconciliation() to authenticated;
grant execute on function public.admin_list_deposit_assets() to authenticated;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant usage on schema public to service_role;
    grant all on all tables in schema public to service_role;
    grant execute on function public.record_provider_observation(text, text, integer, text, text, numeric, integer, text) to service_role;
  end if;
end $$;


-- ===== 20261014130000_manual_deposits_bonus.sql =====
-- Manual wallet deposits, receipt evidence, signup bonus, and email-ready notices.

alter table public.deposit_requests
  add column if not exists payment_declared_at timestamptz,
  add column if not exists receipt_path text,
  add column if not exists receipt_file_name text,
  add column if not exists receipt_content_type text;

alter table public.deposit_requests
  drop constraint if exists deposit_requests_receipt_path_shape;

alter table public.deposit_requests
  add constraint deposit_requests_receipt_path_shape check (
    receipt_path is null
    or receipt_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,180}$'
  );

update public.app_settings
set
  support_email = coalesce(support_email, 'support@creditmee.com'),
  deposit_notification_email = coalesce(deposit_notification_email, 'support@creditmee.com'),
  updated_at = now()
where id = 1;

-- Storage for deposit receipts (private).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'deposit-receipts',
  'deposit-receipts',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do update set
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists deposit_receipts_insert_own on storage.objects;
create policy deposit_receipts_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'deposit-receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists deposit_receipts_select_own on storage.objects;
create policy deposit_receipts_select_own on storage.objects
  for select to authenticated
  using (
    bucket_id = 'deposit-receipts'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.is_admin()
      or public.actor_role() in ('support', 'compliance')
    )
  );

drop policy if exists deposit_receipts_update_own on storage.objects;
create policy deposit_receipts_update_own on storage.objects
  for update to authenticated
  using (
    bucket_id = 'deposit-receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'deposit-receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create or replace function public.grant_signup_bonus(target_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  tx_id uuid;
  cash_account uuid;
  fee_account uuid;
  bonus_cents bigint := 10000;
begin
  tx_id := public.begin_ledger(
    'signup_bonus',
    'profile',
    target_user,
    'Welcome bonus $100.00',
    'signup-bonus:' || target_user::text,
    null
  );
  if tx_id is null then
    return;
  end if;

  cash_account := public.lock_client_account(target_user, 'client_cash');
  fee_account := public.company_account('company_fee_revenue');
  -- Promotional grant: reduce company equity, increase client cash liability.
  perform public.add_ledger_leg(tx_id, fee_account, bonus_cents, 0);
  perform public.add_ledger_leg(tx_id, cash_account, 0, bonus_cents);

  perform public.write_audit(
    null,
    'signup_bonus_credited',
    'profile',
    target_user,
    'Automatic welcome bonus',
    jsonb_build_object('amount_cents', bonus_cents)
  );

  perform public.notify_user(
    target_user,
    'account_notice',
    'Welcome bonus credited',
    'A $100.00 welcome bonus has been credited to your available cash balance.',
    'profile',
    target_user,
    'Your Aztek welcome bonus is ready',
    'A $100.00 welcome bonus has been credited to your Aztek account cash balance. Sign in to view your dashboard. This email does not include wallet details.'
  );
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  country text;
begin
  country := upper(coalesce(new.raw_user_meta_data ->> 'country_code', ''));
  if country !~ '^[A-Z]{2}$' then
    country := null;
  end if;

  insert into public.profiles (id, full_name, country_code)
  values (new.id, left(coalesce(new.raw_user_meta_data ->> 'full_name', ''), 120), country)
  on conflict (id) do nothing;

  insert into public.account_ledger_accounts (account_owner_user_id, account_type)
  values
    (new.id, 'client_cash'),
    (new.id, 'client_cash_reserved'),
    (new.id, 'client_investments')
  on conflict (account_owner_user_id, account_type) where account_owner_user_id is not null
  do nothing;

  perform public.grant_signup_bonus(new.id);

  perform public.notify_user(
    new.id,
    'account_notice',
    'Welcome to Aztek Investment',
    'Your client account was created. Complete onboarding, then fund your managed account when deposits are open.',
    'profile',
    new.id,
    'Welcome to Aztek Investment',
    'Your Aztek account was created. Sign in to finish onboarding and view your welcome bonus. Do not send cryptocurrency until you have deposit instructions inside the portal.'
  );

  return new;
end;
$$;

create or replace function public.mark_deposit_paid(
  deposit_id uuid,
  receipt_path text,
  receipt_file_name text,
  receipt_content_type text,
  transaction_hash text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := public.require_user();
  deposit public.deposit_requests;
  cleaned_hash text;
  path text := nullif(btrim(coalesce(receipt_path, '')), '');
  file_name text := nullif(btrim(coalesce(receipt_file_name, '')), '');
  content_type text := nullif(btrim(coalesce(receipt_content_type, '')), '');
begin
  select * into deposit
  from public.deposit_requests
  where id = mark_deposit_paid.deposit_id
  for update;

  if deposit.id is null or deposit.user_id <> uid then
    raise exception 'Deposit request was not found.';
  end if;
  if deposit.status <> 'awaiting_payment' then
    raise exception 'This deposit is no longer waiting for payment.';
  end if;
  if path is null or file_name is null or content_type is null then
    raise exception 'Upload a payment receipt before marking the deposit as paid.';
  end if;
  if path !~ ('^' || uid::text || '/' || deposit.id::text || '/') then
    raise exception 'The receipt path is not valid for this deposit.';
  end if;
  if content_type not in ('image/jpeg', 'image/png', 'image/webp', 'application/pdf') then
    raise exception 'Upload a JPEG, PNG, WebP, or PDF receipt.';
  end if;

  if transaction_hash is not null and btrim(transaction_hash) <> '' then
    cleaned_hash := public.assert_tx_hash(transaction_hash);
  else
    cleaned_hash := null;
  end if;

  if cleaned_hash is not null then
    if exists (
      select 1 from public.deposit_requests d
      where d.network_identifier_snapshot = deposit.network_identifier_snapshot
        and d.transaction_hash = cleaned_hash
        and d.id <> deposit.id
        and d.status <> 'cancelled'
    ) then
      raise exception 'That transaction hash is already linked to another deposit.';
    end if;
  end if;

  update public.deposit_requests
    set status = 'under_review',
        payment_declared_at = now(),
        receipt_path = path,
        receipt_file_name = left(file_name, 180),
        receipt_content_type = content_type,
        transaction_hash = coalesce(cleaned_hash, deposit.transaction_hash),
        reviewed_by = null,
        review_reason = null
  where id = deposit.id;

  perform public.write_audit(
    uid,
    'deposit_payment_declared',
    'deposit_request',
    deposit.id,
    'Client declared payment and uploaded a receipt',
    jsonb_build_object(
      'reference', deposit.reference,
      'has_hash', cleaned_hash is not null,
      'receipt_content_type', content_type
    )
  );

  perform public.notify_admins(
    'payment_detected',
    'Deposit payment declared',
    'Client marked deposit ' || deposit.reference || ' as paid and uploaded a receipt.',
    'deposit_request',
    deposit.id,
    'Aztek deposit awaits verification',
    'A client marked a deposit as paid and uploaded a receipt. Review the deposit in the admin dashboard before crediting the account. This email does not include a wallet address.'
  );

  perform public.notify_user(
    uid,
    'payment_detected',
    'Payment submitted for review',
    'We received your payment declaration for ' || deposit.reference || '. An administrator will verify the receipt before crediting your account.',
    'deposit_request',
    deposit.id,
    'Your Aztek deposit is under review',
    'We received your payment declaration. An administrator will verify the receipt before your account is credited. Blockchain confirmation alone does not credit the account.'
  );
end;
$$;

create or replace function public.review_deposit(
  deposit_id uuid,
  decision text,
  reason text,
  credit_amount_cents bigint,
  observed_crypto_amount numeric,
  confirmation_count integer,
  observed_address text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := public.require_user();
  deposit public.deposit_requests;
  tx_id uuid;
  cash_account uuid;
  custody_account uuid;
  note text := btrim(coalesce(reason, ''));
  credit bigint := credit_amount_cents;
begin
  if not public.is_admin() then
    raise exception 'You do not have permission to review deposits.';
  end if;
  if char_length(note) < 8 then
    raise exception 'Enter a reason for this deposit decision.';
  end if;
  if decision not in ('approve', 'reject', 'flag') then
    raise exception 'Choose a valid deposit decision.';
  end if;

  select * into deposit from public.deposit_requests where id = review_deposit.deposit_id for update;
  if deposit.id is null then
    raise exception 'Deposit request was not found.';
  end if;
  if deposit.status = 'credited' and decision = 'approve' then
    return;
  end if;
  if deposit.status not in ('awaiting_payment', 'payment_detected', 'confirming', 'under_review') then
    raise exception 'This deposit can no longer be reviewed.';
  end if;

  insert into public.deposit_review_notes (deposit_id, author_id, note)
  values (deposit.id, actor, note);

  if decision = 'flag' then
    update public.deposit_requests
      set status = 'under_review', reviewed_by = actor
    where id = deposit.id;
    perform public.write_audit(actor, 'deposit_flagged', 'deposit_request', deposit.id, note, '{}'::jsonb);
    return;
  end if;

  if decision = 'reject' then
    update public.deposit_requests
      set status = 'rejected', rejected_at = now(), reviewed_by = actor, review_reason = note
    where id = deposit.id;
    perform public.write_audit(actor, 'deposit_rejected', 'deposit_request', deposit.id, note, '{}'::jsonb);
    perform public.notify_user(
      deposit.user_id, 'deposit_rejected', 'Deposit could not be approved',
      'Deposit ' || deposit.reference || ' could not be approved. ' || note,
      'deposit_request', deposit.id,
      'Your Aztek deposit could not be approved',
      'Sign in to view the reason your deposit was not approved.'
    );
    return;
  end if;

  if deposit.payment_declared_at is null and deposit.receipt_path is null and deposit.transaction_hash is null then
    raise exception 'Wait until the client marks the deposit as paid and uploads a receipt, or records a transaction hash.';
  end if;
  if credit is null or credit <= 0 then
    raise exception 'Enter the USD amount to credit after verification.';
  end if;
  if observed_address is not null and btrim(observed_address) <> ''
     and btrim(observed_address) <> deposit.receiving_address_display then
    raise exception 'The observed receiving address does not match the deposit instructions. Flag the payment instead of crediting it.';
  end if;

  tx_id := public.begin_ledger(
    'deposit_credit', 'deposit_request', deposit.id,
    'Deposit credited ' || deposit.reference,
    'deposit-credit:' || deposit.id::text,
    actor
  );
  if tx_id is not null then
    cash_account := public.lock_client_account(deposit.user_id, 'client_cash');
    custody_account := public.company_account('company_custody_cash');
    perform public.add_ledger_leg(tx_id, custody_account, credit, 0);
    perform public.add_ledger_leg(tx_id, cash_account, 0, credit);
  end if;

  if deposit.transaction_hash is not null then
    insert into public.blockchain_transactions (
      deposit_id, network_identifier, transaction_hash, output_index, asset_identifier,
      to_address, raw_amount, confirmation_count, verification_status
    ) values (
      deposit.id, deposit.network_identifier_snapshot, deposit.transaction_hash, 0,
      deposit.asset_symbol_snapshot, deposit.receiving_address_display,
      coalesce(observed_crypto_amount, 0), coalesce(confirmation_count, 0), 'manual_review'
    )
    on conflict (network_identifier, transaction_hash, output_index)
    do update set
      confirmation_count = excluded.confirmation_count,
      raw_amount = excluded.raw_amount,
      last_checked_at = now(),
      verification_status = 'manual_review',
      deposit_id = excluded.deposit_id;
  end if;

  update public.deposit_requests
    set status = 'credited',
        credited_at = coalesce(credited_at, now()),
        credited_amount_cents = credit,
        observed_crypto_amount = coalesce(review_deposit.observed_crypto_amount, observed_crypto_amount),
        observed_address = coalesce(nullif(btrim(observed_address), ''), receiving_address_display),
        confirmation_count = coalesce(review_deposit.confirmation_count, confirmation_count, 0),
        reviewed_by = actor
  where id = deposit.id;

  perform public.write_audit(actor, 'deposit_credited', 'deposit_request', deposit.id, note,
    jsonb_build_object(
      'credit_amount_cents', credit,
      'requested_amount_cents', deposit.requested_amount_cents,
      'manual_receipt', deposit.receipt_path is not null
    ));
  perform public.notify_user(
    deposit.user_id, 'deposit_credited', 'Deposit credited',
    'Deposit ' || deposit.reference || ' has been confirmed and credited to your account.',
    'deposit_request', deposit.id,
    'Your Aztek deposit was credited',
    'Your deposit has been confirmed and credited. Sign in to view your account. This email does not include a wallet address.'
  );
end;
$$;

grant execute on function public.mark_deposit_paid(uuid, text, text, text, text) to authenticated;
grant execute on function public.grant_signup_bonus(uuid) to service_role;

-- Backfill clients created before this schema was applied.
insert into public.profiles (id, full_name, country_code)
select
  u.id,
  left(coalesce(u.raw_user_meta_data ->> 'full_name', ''), 120),
  case
    when upper(coalesce(u.raw_user_meta_data ->> 'country_code', '')) ~ '^[A-Z]{2}$'
      then upper(u.raw_user_meta_data ->> 'country_code')
    else null
  end
from auth.users u
on conflict (id) do nothing;

insert into public.account_ledger_accounts (account_owner_user_id, account_type)
select u.id, t.account_type
from auth.users u
cross join (values
  ('client_cash'::public.ledger_account_type),
  ('client_cash_reserved'::public.ledger_account_type),
  ('client_investments'::public.ledger_account_type)
) as t(account_type)
on conflict (account_owner_user_id, account_type) where account_owner_user_id is not null
do nothing;

do $$
declare
  uid uuid;
begin
  for uid in select id from public.profiles where role = 'client'
  loop
    perform public.grant_signup_bonus(uid);
  end loop;
end;
$$;


-- ===== 20261014140000_seed_btc_wallet.sql =====
-- Seed the verified Bitcoin receiving wallet for manual deposits.

insert into public.deposit_assets (
  symbol,
  asset_name,
  network_name,
  network_identifier,
  asset_contract,
  receiving_address,
  address_is_shared,
  address_verified_at,
  minimum_deposit_cents,
  maximum_deposit_cents,
  required_confirmations,
  deposit_enabled,
  withdrawal_enabled,
  custody_provider,
  decimals
) values (
  'BTC',
  'Bitcoin',
  'Bitcoin',
  'bitcoin',
  null,
  'bc1qwfnufgkd4tuwzxngpx9h2rf6kglgjuqqgs0qze',
  true,
  now(),
  5000,
  100000000,
  1,
  true,
  false,
  'manual_wallet',
  8
)
on conflict (symbol, network_identifier) do update set
  asset_name = excluded.asset_name,
  network_name = excluded.network_name,
  receiving_address = excluded.receiving_address,
  address_is_shared = excluded.address_is_shared,
  address_verified_at = excluded.address_verified_at,
  minimum_deposit_cents = excluded.minimum_deposit_cents,
  maximum_deposit_cents = excluded.maximum_deposit_cents,
  required_confirmations = excluded.required_confirmations,
  deposit_enabled = excluded.deposit_enabled,
  custody_provider = excluded.custody_provider,
  decimals = excluded.decimals,
  updated_at = now();

update public.app_settings
set
  deposits_enabled = true,
  support_email = coalesce(support_email, 'support@creditmee.com'),
  deposit_notification_email = coalesce(deposit_notification_email, 'support@creditmee.com'),
  updated_at = now()
where id = 1;


-- ===== 20261014140100_seed_usdt_bep20.sql =====
-- Seed USDT on BNB Smart Chain (BEP20) for manual deposits.

insert into public.deposit_assets (
  symbol,
  asset_name,
  network_name,
  network_identifier,
  asset_contract,
  receiving_address,
  address_is_shared,
  address_verified_at,
  minimum_deposit_cents,
  maximum_deposit_cents,
  required_confirmations,
  deposit_enabled,
  withdrawal_enabled,
  custody_provider,
  decimals
) values (
  'USDT',
  'Tether USD',
  'BNB Smart Chain (BEP20)',
  'bnb-smart-chain',
  null,
  '0x871309EA406CDbB36153E4D887fFc223b98cDc16',
  true,
  now(),
  5000,
  100000000,
  1,
  true,
  false,
  'manual_wallet',
  6
)
on conflict (symbol, network_identifier) do update set
  asset_name = excluded.asset_name,
  network_name = excluded.network_name,
  receiving_address = excluded.receiving_address,
  address_is_shared = excluded.address_is_shared,
  address_verified_at = excluded.address_verified_at,
  minimum_deposit_cents = excluded.minimum_deposit_cents,
  maximum_deposit_cents = excluded.maximum_deposit_cents,
  required_confirmations = excluded.required_confirmations,
  deposit_enabled = excluded.deposit_enabled,
  custody_provider = excluded.custody_provider,
  decimals = excluded.decimals,
  updated_at = now();

update public.app_settings
set
  deposits_enabled = true,
  support_email = coalesce(support_email, 'support@creditmee.com'),
  deposit_notification_email = coalesce(deposit_notification_email, 'support@creditmee.com'),
  updated_at = now()
where id = 1;

