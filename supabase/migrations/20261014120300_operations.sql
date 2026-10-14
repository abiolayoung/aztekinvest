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
