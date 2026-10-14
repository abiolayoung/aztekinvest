import { notFound } from "next/navigation";
import { reviewDepositAction } from "@/lib/actions/admin";
import { StateForm } from "@/components/forms/state-form";
import { Input, Label, Textarea } from "@/components/ui/fields";
import { Money, PageIntro } from "@/components/ui/page";
import { can } from "@/lib/auth/permissions";
import { requireUser } from "@/lib/auth/session";
import { formatTimestamp } from "@/lib/format/date";
import { accountStatusLabel, depositStatusLabel, labelFor, verificationLabel } from "@/lib/format/labels";
import { createAdminClient } from "@/lib/supabase/admin";

export default async function AdminDepositDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "reviewDeposits")) return <p>You do not have permission to review deposits.</p>;
  const { data: deposit } = await supabase.from("deposit_requests").select("*").eq("id", id).maybeSingle();
  if (!deposit) notFound();
  const [{ data: client }, { data: notes }] = await Promise.all([
    supabase.from("profiles").select("full_name, verification_status, account_status, email_verified_at").eq("id", deposit.user_id).maybeSingle(),
    supabase.from("deposit_review_notes").select("id, note, created_at").eq("deposit_id", deposit.id).order("created_at", { ascending: false }),
  ]);

  let receiptUrl: string | null = null;
  if (deposit.receipt_path) {
    const admin = createAdminClient();
    if (admin) {
      const { data } = await admin.storage.from("deposit-receipts").createSignedUrl(deposit.receipt_path, 60 * 30);
      receiptUrl = data?.signedUrl ?? null;
    }
  }

  const defaultCredit = deposit.requested_amount_cents
    ? (Number(deposit.requested_amount_cents) / 100).toFixed(2)
    : "";
  const hasReceipt = Boolean(deposit.receipt_path || deposit.receipt_file_name || deposit.payment_declared_at);
  const canCredit =
    hasReceipt &&
    deposit.status !== "credited" &&
    deposit.status !== "rejected" &&
    deposit.status !== "cancelled" &&
    deposit.status !== "expired";

  return (
    <div className="grid gap-6 lg:grid-cols-2">
      <div>
        <PageIntro
          title={deposit.reference}
          body="Verify the uploaded receipt against the expected wallet details. When the payment checks out, press Received to credit the client dashboard."
        />

        <ol className="mb-4 space-y-2 rounded-card border border-line bg-white p-4 text-sm">
          <Step done={hasReceipt} label="Client uploaded a payment receipt" />
          <Step done={deposit.status === "credited"} label="Admin verifies the receipt" />
          <Step done={deposit.status === "credited"} label="Admin presses Received to credit available cash" />
        </ol>

        <dl className="space-y-2 rounded-card border border-line bg-white p-4 text-sm">
          <div>Client: {client?.full_name} · {labelFor(verificationLabel, client?.verification_status ?? "")} · {labelFor(accountStatusLabel, client?.account_status ?? "")}</div>
          <div>Status: {labelFor(depositStatusLabel, deposit.status)}</div>
          <div>Requested: <Money cents={deposit.requested_amount_cents} /></div>
          {deposit.credited_amount_cents ? (
            <div>Credited: <Money cents={deposit.credited_amount_cents} /></div>
          ) : null}
          <div>Asset: {deposit.asset_symbol_snapshot} on {deposit.network_name_snapshot} ({deposit.network_identifier_snapshot})</div>
          <div className="break-all">Expected address: <span className="font-mono text-xs">{deposit.receiving_address_display}</span></div>
          <div className="break-all">Transaction hash: <span className="font-mono text-xs">{deposit.transaction_hash ?? "Not provided"}</span></div>
          <div>Client marked paid: {deposit.payment_declared_at ? formatTimestamp(deposit.payment_declared_at) : "Not yet"}</div>
          <div>Receipt file: {deposit.receipt_file_name ?? "Not uploaded"}</div>
        </dl>

        <div className="mt-4 rounded-card border border-line bg-white p-4">
          <p className="text-sm font-medium">Uploaded receipt</p>
          {!hasReceipt ? (
            <p className="mt-2 text-sm text-ink-muted">
              Waiting for the client to upload a receipt. You cannot mark this payment as received until a receipt is available.
            </p>
          ) : receiptUrl ? (
            deposit.receipt_content_type?.startsWith("image/") ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={receiptUrl} alt="Client payment receipt" className="mt-3 max-h-[28rem] w-full rounded-lg object-contain" />
            ) : (
              <a href={receiptUrl} target="_blank" rel="noreferrer" className="mt-3 inline-flex text-sm text-brand">
                Open receipt file ({deposit.receipt_file_name})
              </a>
            )
          ) : (
            <p className="mt-2 text-sm text-ink-muted">Receipt is on file, but a preview link could not be created.</p>
          )}
        </div>

        <div className="mt-4 space-y-2">
          {(notes ?? []).map((note) => (
            <p key={note.id} className="rounded-lg bg-muted px-3 py-2 text-sm">
              <span className="text-xs text-ink-muted">{formatTimestamp(note.created_at)} · </span>
              {note.note}
            </p>
          ))}
        </div>
      </div>

      <div className="space-y-4">
        {deposit.status === "credited" ? (
          <div className="rounded-card border border-line bg-muted p-5 text-sm text-ink-muted">
            Payment already marked received and credited. The client dashboard cash balance includes{" "}
            <Money cents={deposit.credited_amount_cents ?? deposit.requested_amount_cents} />.
          </div>
        ) : null}

        {deposit.status === "rejected" ? (
          <div className="rounded-card border border-line bg-muted p-5 text-sm text-ink-muted">
            This deposit was rejected{deposit.review_reason ? `: ${deposit.review_reason}` : "."}
          </div>
        ) : null}

        {canCredit ? (
          <section className="rounded-card border border-line bg-white p-5">
            <h2 className="text-base font-medium">Verify and mark received</h2>
            <p className="mt-1 text-sm text-ink-muted">
              Check the receipt on the left. If the payment is valid, press <strong className="font-medium text-ink">Received</strong> to credit the client dashboard once.
            </p>
            <div className="mt-4">
              <StateForm action={reviewDepositAction} submitLabel="Received" pendingLabel="Crediting dashboard...">
                <input type="hidden" name="depositId" value={deposit.id} />
                <input type="hidden" name="decision" value="approve" />
                <input type="hidden" name="observedAddress" value={deposit.receiving_address_display ?? ""} />
                <div>
                  <Label htmlFor="creditAmount">USD amount to credit</Label>
                  <Input id="creditAmount" name="creditAmount" placeholder="0.00" defaultValue={defaultCredit} required />
                  <p className="mt-1 text-xs text-ink-muted">
                    Defaults to the requested amount. Adjust only if the verified payment differs.
                  </p>
                </div>
                <div>
                  <Label htmlFor="reason">Verification note</Label>
                  <Textarea
                    id="reason"
                    name="reason"
                    required
                    placeholder="Example: Receipt matches expected USDT BEP20 transfer and requested amount."
                  />
                </div>
                <label className="flex items-start gap-2 text-sm">
                  <input className="mt-1" type="checkbox" name="confirmed" required />
                  <span>I verified the uploaded receipt and confirm this payment should be marked received and credited once.</span>
                </label>
              </StateForm>
            </div>
          </section>
        ) : null}

        {!canCredit && deposit.status !== "credited" && deposit.status !== "rejected" ? (
          <div className="rounded-card border border-line bg-muted p-5 text-sm text-ink-muted">
            The Received button appears after the client uploads a receipt and marks the deposit as paid.
          </div>
        ) : null}

        {canCredit ? (
          <details className="rounded-card border border-line bg-white p-5">
            <summary className="cursor-pointer text-sm font-medium">Other actions</summary>
            <div className="mt-4 space-y-6">
              <StateForm action={reviewDepositAction} submitLabel="Keep under review" pendingLabel="Saving...">
                <input type="hidden" name="depositId" value={deposit.id} />
                <input type="hidden" name="decision" value="flag" />
                <input type="hidden" name="creditAmount" value={defaultCredit} />
                <div>
                  <Label htmlFor="flagReason">Note</Label>
                  <Textarea id="flagReason" name="reason" required placeholder="Why this needs more review." />
                </div>
              </StateForm>
              <StateForm action={reviewDepositAction} submitLabel="Reject payment" pendingLabel="Rejecting...">
                <input type="hidden" name="depositId" value={deposit.id} />
                <input type="hidden" name="decision" value="reject" />
                <input type="hidden" name="creditAmount" value={defaultCredit} />
                <div>
                  <Label htmlFor="rejectReason">Rejection reason</Label>
                  <Textarea id="rejectReason" name="reason" required placeholder="Explain why the payment is rejected." />
                </div>
              </StateForm>
            </div>
          </details>
        ) : null}
      </div>
    </div>
  );
}

function Step({ done, label }: { done: boolean; label: string }) {
  return (
    <li className="flex items-start gap-2">
      <span className={`mt-0.5 inline-block h-2.5 w-2.5 shrink-0 rounded-full ${done ? "bg-brand" : "bg-line"}`} />
      <span className={done ? "text-ink" : "text-ink-muted"}>{label}</span>
    </li>
  );
}
