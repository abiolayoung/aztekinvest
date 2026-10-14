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
