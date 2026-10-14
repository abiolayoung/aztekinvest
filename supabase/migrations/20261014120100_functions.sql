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
