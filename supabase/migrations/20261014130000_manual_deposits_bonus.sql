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
  perform set_config('row_security', 'off', true);

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

  if mark_deposit_paid.transaction_hash is not null
     and btrim(mark_deposit_paid.transaction_hash) <> '' then
    cleaned_hash := public.assert_tx_hash(mark_deposit_paid.transaction_hash);
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
  observed_crypto numeric := review_deposit.observed_crypto_amount;
  observed_conf integer := review_deposit.confirmation_count;
  observed_addr text := nullif(btrim(coalesce(review_deposit.observed_address, '')), '');
begin
  perform set_config('row_security', 'off', true);

  if not public.is_admin() then
    raise exception 'You do not have permission to review deposits.';
  end if;
  if char_length(note) < 8 then
    raise exception 'Enter a reason for this deposit decision.';
  end if;
  if decision not in ('approve', 'reject', 'flag') then
    raise exception 'Choose a valid deposit decision.';
  end if;

  select * into deposit
  from public.deposit_requests
  where id = review_deposit.deposit_id
  for update;

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
      set status = 'rejected',
          rejected_at = now(),
          reviewed_by = actor,
          review_reason = note
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

  if deposit.payment_declared_at is null
     and deposit.receipt_path is null
     and deposit.transaction_hash is null then
    raise exception 'Wait until the client marks the deposit as paid and uploads a receipt, or records a transaction hash.';
  end if;
  if credit is null or credit <= 0 then
    raise exception 'Enter the USD amount to credit after verification.';
  end if;
  if observed_addr is not null
     and observed_addr <> deposit.receiving_address_display then
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
      coalesce(observed_crypto, 0), coalesce(observed_conf, 0), 'manual_review'
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
        credited_at = coalesce(deposit_requests.credited_at, now()),
        credited_amount_cents = credit,
        observed_crypto_amount = coalesce(observed_crypto, deposit_requests.observed_crypto_amount),
        observed_address = coalesce(observed_addr, deposit_requests.receiving_address_display),
        confirmation_count = coalesce(observed_conf, deposit_requests.confirmation_count, 0),
        reviewed_by = actor,
        payment_declared_at = coalesce(deposit_requests.payment_declared_at, now())
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
