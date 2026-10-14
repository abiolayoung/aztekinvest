import { cancelWithdrawalAction, requestWithdrawalAction } from "@/lib/actions/withdrawals";
import { StateForm } from "@/components/forms/state-form";
import { StatusBadge } from "@/components/ui/badge";
import { Input, Label, Select } from "@/components/ui/fields";
import { Money, PageIntro } from "@/components/ui/page";
import { requireUser } from "@/lib/auth/session";
import { mapSummary } from "@/lib/data/summary";
import { formatTimestamp } from "@/lib/format/date";
import { formatUsdCents } from "@/lib/finance/money";
import { labelFor, withdrawalStatusLabel } from "@/lib/format/labels";

export default async function WithdrawalsPage() {
  const { supabase, user, profile } = await requireUser();
  const [settingsResult, assetsResult, summaryResult, historyResult] = await Promise.all([
    supabase.rpc("get_public_settings"),
    supabase.from("deposit_assets").select("id, symbol, network_name, network_identifier, withdrawal_fee_cents, withdrawal_enabled").eq("withdrawal_enabled", true),
    supabase.rpc("get_account_summary", { target_user: user.id }),
    supabase.from("withdrawal_requests").select("id, reference, requested_amount_cents, payout_amount_cents, fee_amount_cents, status, asset_symbol_snapshot, network_name_snapshot, created_at, review_reason").eq("user_id", user.id).order("created_at", { ascending: false }),
  ]);
  const settings = Array.isArray(settingsResult.data) ? settingsResult.data[0] : settingsResult.data;
  const summaryRow = Array.isArray(summaryResult.data) ? summaryResult.data[0] : summaryResult.data;
  const summary = summaryRow ? mapSummary(summaryRow) : null;
  const eligible = Boolean(profile.email_verified_at) && profile.verification_status === "verified" && profile.account_status === "active";
  const open = Boolean(settings?.withdrawals_enabled) && (assetsResult.data ?? []).length > 0 && eligible;

  return (
    <div className="grid gap-6 lg:grid-cols-[360px_1fr]">
      <div>
        <PageIntro title="Withdrawals" body={settings?.withdrawal_processing_notice || "Withdrawal requests are reviewed before payment."} />
        <p className="mb-4 text-sm">Available balance {summary ? <Money cents={summary.cashCents} /> : "could not be loaded"}.</p>
        {open ? (
          <StateForm action={requestWithdrawalAction} submitLabel="Submit request" pendingLabel="Submitting...">
            <div>
              <Label htmlFor="amount">Amount in USD</Label>
              <Input id="amount" name="amount" inputMode="decimal" required />
            </div>
            <div>
              <Label htmlFor="assetId">Asset and network</Label>
              <Select id="assetId" name="assetId" defaultValue="" required>
                <option value="" disabled>Choose</option>
                {(assetsResult.data ?? []).map((asset) => (
                  <option key={asset.id} value={asset.id}>
                    {asset.symbol} · {asset.network_name} · fee {formatUsdCents(asset.withdrawal_fee_cents)}
                  </option>
                ))}
              </Select>
            </div>
            <div>
              <Label htmlFor="destinationAddress">Receiving address</Label>
              <Input id="destinationAddress" name="destinationAddress" autoComplete="off" required />
            </div>
            <label className="flex items-start gap-2 text-sm">
              <input className="mt-1" type="checkbox" name="acknowledged" />
              <span>I confirm the address, asset, and network. Aztek does not promise a fixed payout time.</span>
            </label>
          </StateForm>
        ) : (
          <p className="rounded-card border border-line bg-white p-4 text-sm text-ink-muted">
            Withdrawals are not currently open. A request can be made after the account is approved, an asset is configured, and withdrawals are enabled.
          </p>
        )}
      </div>
      <div className="space-y-3">
        {(historyResult.data ?? []).length === 0 ? <p className="text-sm text-ink-muted">No withdrawal requests yet.</p> : null}
        {(historyResult.data ?? []).map((row) => (
          <article key={row.id} className="rounded-card border border-line bg-white p-4 text-sm">
            <div className="flex items-center justify-between gap-3">
              <h2 className="font-medium">{row.reference}</h2>
              <StatusBadge status={row.status} label={labelFor(withdrawalStatusLabel, row.status)} />
            </div>
            <p className="mt-2">Requested <Money cents={row.requested_amount_cents} /> · Fee {row.fee_amount_cents === null ? "—" : <Money cents={row.fee_amount_cents} />} · Payout {row.payout_amount_cents === null ? "—" : <Money cents={row.payout_amount_cents} />}</p>
            <p className="mt-1 text-ink-muted">{row.asset_symbol_snapshot} · {row.network_name_snapshot} · {formatTimestamp(row.created_at)}</p>
            {row.review_reason ? <p className="mt-2">{row.review_reason}</p> : null}
            {row.status === "requested" || row.status === "under_review" ? (
              <form action={cancelWithdrawalAction} className="mt-3">
                <input type="hidden" name="withdrawalId" value={row.id} />
                <button className="text-sm text-ink-muted" type="submit">Cancel request</button>
              </form>
            ) : null}
          </article>
        ))}
      </div>
    </div>
  );
}
