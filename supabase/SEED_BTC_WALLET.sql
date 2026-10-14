-- Run this in the Supabase SQL editor after FULL_SETUP.sql
-- if you already applied earlier migrations.

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
