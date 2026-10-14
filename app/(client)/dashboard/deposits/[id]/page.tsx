import { notFound } from "next/navigation";
import QRCode from "qrcode";
import { cancelDepositAction, markDepositPaidAction } from "@/lib/actions/deposits";
import { PaymentInstructions } from "@/components/deposits/payment-instructions";
import { StateForm } from "@/components/forms/state-form";
import { StatusBadge } from "@/components/ui/badge";
import { Input, Label } from "@/components/ui/fields";
import { Money, PageIntro } from "@/components/ui/page";
import { officialWalletQrPath } from "@/lib/crypto/wallet-display";
import { requireUser } from "@/lib/auth/session";
import { formatTimestamp } from "@/lib/format/date";
import { depositStatusLabel, labelFor } from "@/lib/format/labels";

export default async function DepositDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase, user } = await requireUser();
  const { data: deposit } = await supabase.from("deposit_requests").select("*").eq("id", id).eq("user_id", user.id).maybeSingle();
  if (!deposit) notFound();

  const address = String(deposit.receiving_address_display ?? "");
  const officialQr = officialWalletQrPath(
    String(deposit.asset_symbol_snapshot ?? ""),
    String(deposit.network_identifier_snapshot ?? ""),
  );
  const generatedQr =
    !officialQr && /^[A-Za-z0-9]{20,128}$/.test(address)
      ? await QRCode.toDataURL(address, { margin: 1, width: 220, color: { dark: "#123C32", light: "#ffffff" } })
      : null;
  const qrSrc = officialQr ?? generatedQr;
  const awaitingPayment = deposit.status === "awaiting_payment";
  const showPayment =
    deposit.status !== "credited" &&
    deposit.status !== "rejected" &&
    deposit.status !== "cancelled" &&
    deposit.status !== "expired";

  return (
    <div className="mx-auto max-w-form">
      <PageIntro
        title={deposit.reference}
        body="Complete the payment using the wallet details below, then upload your receipt so we can verify and credit your account."
      />
      <div className="mb-4">
        <StatusBadge status={deposit.status} label={labelFor(depositStatusLabel, deposit.status)} />
      </div>

      <dl className="space-y-3 rounded-card border border-line bg-white p-5 text-sm">
        <Detail label="Requested amount" value={<Money cents={deposit.requested_amount_cents} />} />
        <Detail label="Credited amount" value={deposit.credited_amount_cents ? <Money cents={deposit.credited_amount_cents} /> : "Not credited yet"} />
        <Detail label="Asset" value={`${deposit.asset_symbol_snapshot} · ${deposit.asset_name_snapshot}`} />
        <Detail label="Network" value={`${deposit.network_name_snapshot} (${deposit.network_identifier_snapshot})`} />
        <Detail label="Submitted" value={formatTimestamp(deposit.submitted_at)} />
        {deposit.payment_declared_at ? <Detail label="Marked paid" value={formatTimestamp(deposit.payment_declared_at)} /> : null}
        {deposit.receipt_file_name ? <Detail label="Receipt" value={deposit.receipt_file_name} /> : null}
        {deposit.review_reason && deposit.status === "rejected" ? <Detail label="Reason" value={deposit.review_reason} /> : null}
      </dl>

      {showPayment ? (
        <>
          <PaymentInstructions
            reference={deposit.reference}
            address={address}
            assetSymbol={String(deposit.asset_symbol_snapshot)}
            assetName={String(deposit.asset_name_snapshot)}
            networkName={String(deposit.network_name_snapshot)}
            networkIdentifier={String(deposit.network_identifier_snapshot)}
            requestedAmountCents={deposit.requested_amount_cents}
            qrSrc={qrSrc}
            addressIsShared={Boolean(deposit.address_is_shared_snapshot)}
          />

          {awaitingPayment ? (
            <section className="mt-4 rounded-card border border-line bg-white p-5">
              <h2 className="text-base font-medium">After you send the payment</h2>
              <p className="mt-1 text-sm leading-6 text-ink-muted">
                Upload your receipt, then confirm that you have paid. Your balance will update only after administrator verification.
              </p>
              <div className="mt-4">
                <StateForm
                  action={markDepositPaidAction}
                  submitLabel="I have paid"
                  pendingLabel="Submitting payment..."
                >
                  <input type="hidden" name="depositId" value={deposit.id} />
                  <div>
                    <Label htmlFor="receipt">Payment receipt</Label>
                    <Input id="receipt" name="receipt" type="file" accept="image/jpeg,image/png,image/webp,application/pdf" required />
                    <p className="mt-1 text-xs text-ink-muted">
                      JPEG, PNG, WebP, or PDF up to 5 MB. A wallet screenshot or transaction PDF is preferred.
                    </p>
                  </div>
                  <div>
                    <Label htmlFor="transactionHash">Transaction ID / hash (optional)</Label>
                    <Input id="transactionHash" name="transactionHash" className="font-mono" autoComplete="off" />
                    <p className="mt-1 text-xs text-ink-muted">If your wallet shows a transaction ID, add it here to speed up review.</p>
                  </div>
                </StateForm>
              </div>
              <form action={cancelDepositAction} className="mt-4">
                <input type="hidden" name="depositId" value={deposit.id} />
                <button className="text-sm text-ink-muted" type="submit">
                  Cancel this unpaid request
                </button>
              </form>
            </section>
          ) : null}

          {deposit.status === "under_review" ? (
            <p className="mt-4 rounded-lg border border-line bg-muted px-3 py-2 text-sm text-ink-muted">
              Your payment is under review. You will be notified when it is credited or if more information is needed.
            </p>
          ) : null}
        </>
      ) : null}

      <p className="mt-4 text-sm text-ink-muted">
        If anything looks wrong before you send funds, contact support and do not make a second transfer.
      </p>
    </div>
  );
}

function Detail({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-start justify-between gap-4">
      <dt className="text-ink-muted">{label}</dt>
      <dd className="text-right">{value}</dd>
    </div>
  );
}
