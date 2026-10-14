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
