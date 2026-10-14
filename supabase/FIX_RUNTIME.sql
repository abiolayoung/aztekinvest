-- Apply in Supabase SQL editor now.
-- Fixes: signup trigger under FORCE RLS, deposit asset listing, and rate-limit ambiguity.

drop function if exists public.consume_rate_limit(text, integer, integer);

create or replace function public.consume_rate_limit(
  p_bucket_key text,
  max_hits integer,
  window_seconds integer
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  bucket_window timestamptz;
  current_count integer;
begin
  perform set_config('row_security', 'off', true);
  bucket_window := to_timestamp(
    floor(extract(epoch from now()) / window_seconds) * window_seconds
  );
  insert into public.rate_limits as rl (bucket_key, window_start, hit_count)
  values (p_bucket_key, bucket_window, 1)
  on conflict (bucket_key, window_start)
  do update set hit_count = rl.hit_count + 1
  returning hit_count into current_count;

  if current_count > max_hits then
    raise exception 'Too many requests. Please wait and try again.';
  end if;
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
  perform set_config('row_security', 'off', true);
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
  perform set_config('row_security', 'off', true);
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
  perform set_config('row_security', 'off', true);
  clean := coalesce(metadata, '{}'::jsonb)
    - 'password' - 'token' - 'access_token' - 'refresh_token'
    - 'secret' - 'private_key' - 'seed' - 'seed_phrase' - 'service_role';
  insert into public.audit_logs (actor_user_id, action, entity_type, entity_id, reason, metadata)
  values (actor, action, entity_type, entity_id, reason, clean);
end;
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
  perform set_config('row_security', 'off', true);
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
  perform set_config('row_security', 'off', true);
  if not (
    (debit_amount > 0 and credit_amount = 0)
    or (credit_amount > 0 and debit_amount = 0)
  ) then
    raise exception 'Ledger legs must be one-sided.';
  end if;
  insert into public.ledger_entries (ledger_transaction_id, account_id, debit_amount, credit_amount)
  values (ledger_transaction_id, account_id, debit_amount, credit_amount);
end;
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
  perform set_config('row_security', 'off', true);
  select id into account_id
  from public.account_ledger_accounts
  where account_owner_user_id = target_user and account_type = kind
  for update;
  if account_id is null then
    raise exception 'Ledger account was not found.';
  end if;
  return account_id;
end;
$$;

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
  perform set_config('row_security', 'off', true);
  tx_id := public.begin_ledger(
    'signup_bonus', 'profile', target_user, 'Welcome bonus $100.00',
    'signup-bonus:' || target_user::text, null
  );
  if tx_id is null then
    return;
  end if;
  cash_account := public.lock_client_account(target_user, 'client_cash');
  fee_account := public.company_account('company_fee_revenue');
  perform public.add_ledger_leg(tx_id, fee_account, bonus_cents, 0);
  perform public.add_ledger_leg(tx_id, cash_account, 0, bonus_cents);
  perform public.write_audit(null, 'signup_bonus_credited', 'profile', target_user, 'Automatic welcome bonus',
    jsonb_build_object('amount_cents', bonus_cents));
  perform public.notify_user(
    target_user, 'account_notice', 'Welcome bonus credited',
    'A $100.00 welcome bonus has been credited to your available cash balance.',
    'profile', target_user, 'Your Aztek welcome bonus is ready',
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
  perform set_config('row_security', 'off', true);
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
    new.id, 'account_notice', 'Welcome to Aztek Investment',
    'Your client account was created. Complete onboarding, then fund your managed account when deposits are open.',
    'profile', new.id, 'Welcome to Aztek Investment',
    'Your Aztek account was created. Sign in to finish onboarding and view your welcome bonus. Do not send cryptocurrency until you have deposit instructions inside the portal.'
  );
  return new;
end;
$$;

-- Safe asset list for clients (no receiving addresses).
create or replace function public.list_enabled_deposit_assets()
returns table (
  id uuid,
  symbol text,
  asset_name text,
  network_name text,
  network_identifier text,
  minimum_deposit_cents bigint,
  maximum_deposit_cents bigint,
  required_confirmations integer,
  address_is_shared boolean,
  deposit_enabled boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform set_config('row_security', 'off', true);
  return query
  select
    a.id, a.symbol, a.asset_name, a.network_name, a.network_identifier,
    a.minimum_deposit_cents, a.maximum_deposit_cents, a.required_confirmations,
    a.address_is_shared, a.deposit_enabled
  from public.deposit_assets a
  where a.deposit_enabled = true
  order by a.symbol, a.network_name;
end;
$$;

grant execute on function public.list_enabled_deposit_assets() to authenticated;

grant select (
  id, symbol, asset_name, network_name, network_identifier,
  minimum_deposit_cents, maximum_deposit_cents, required_confirmations,
  deposit_enabled, withdrawal_enabled, withdrawal_fee_cents, decimals, address_is_shared
) on public.deposit_assets to authenticated;

-- Ensure deposit mutation helpers can write under FORCE RLS.
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
  perform set_config('row_security', 'off', true);
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

grant execute on function public.create_deposit_request(bigint, uuid, uuid, boolean) to authenticated;
