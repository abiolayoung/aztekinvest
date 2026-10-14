-- Fix: signup fails because security-definer writers hit FORCE RLS with no insert policies.
-- Run this in the Supabase SQL editor, then try registering again.

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
