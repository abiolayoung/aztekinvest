-- Fixes: "column reference transaction_hash is ambiguous"
-- and FORCE RLS blocking writes inside security definer.

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

grant execute on function public.mark_deposit_paid(uuid, text, text, text, text) to authenticated;
