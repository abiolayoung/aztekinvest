-- Admin can mark receipt-submitted deposits as received and credit cash once.
-- Fixes FORCE RLS + ambiguous column refs in review_deposit,
-- and deferred ledger balance checks under the authenticated role.

create or replace function public.enforce_ledger_balance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  debit_sum bigint;
  credit_sum bigint;
  tx_id uuid;
begin
  perform set_config('row_security', 'off', true);
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

create or replace function public.company_account(kind public.ledger_account_type)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  account_id uuid;
begin
  perform set_config('row_security', 'off', true);
  select id into account_id
  from public.account_ledger_accounts
  where account_owner_user_id is null and account_type = kind
  limit 1;
  if account_id is null then
    raise exception 'Company ledger account was not found.';
  end if;
  return account_id;
end;
$$;

create or replace function public.is_admin()
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform set_config('row_security', 'off', true);
  return exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role = 'admin'
      and account_status not in ('suspended', 'closed')
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
      deposit.user_id,
      'deposit_rejected',
      'Deposit could not be approved',
      'Deposit ' || deposit.reference || ' could not be approved. ' || note,
      'deposit_request',
      deposit.id,
      'Your Aztek deposit could not be approved',
      'Sign in to view the reason your deposit was not approved.'
    );
    return;
  end if;

  -- Approve / mark payment received and credit once.
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
    'deposit_credit',
    'deposit_request',
    deposit.id,
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
      deposit.id,
      deposit.network_identifier_snapshot,
      deposit.transaction_hash,
      0,
      deposit.asset_symbol_snapshot,
      deposit.receiving_address_display,
      coalesce(observed_crypto, 0),
      coalesce(observed_conf, 0),
      'manual_review'
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

  perform public.write_audit(
    actor,
    'deposit_credited',
    'deposit_request',
    deposit.id,
    note,
    jsonb_build_object(
      'credit_amount_cents', credit,
      'requested_amount_cents', deposit.requested_amount_cents,
      'manual_receipt', deposit.receipt_path is not null
    )
  );
  perform public.notify_user(
    deposit.user_id,
    'deposit_credited',
    'Deposit credited',
    'Deposit ' || deposit.reference || ' has been confirmed and credited to your account.',
    'deposit_request',
    deposit.id,
    'Your Aztek deposit was credited',
    'Your deposit has been confirmed and credited. Sign in to view your account. This email does not include a wallet address.'
  );
end;
$$;

grant execute on function public.review_deposit(uuid, text, text, bigint, numeric, integer, text) to authenticated;
