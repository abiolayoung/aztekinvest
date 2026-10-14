import { reviewWithdrawalAction } from "@/lib/actions/admin";
import { StateForm } from "@/components/forms/state-form";
import { Input, Label, Select, Textarea } from "@/components/ui/fields";
import { Money, PageIntro } from "@/components/ui/page";
import { can } from "@/lib/auth/permissions";
import { requireUser } from "@/lib/auth/session";
import { labelFor, withdrawalStatusLabel } from "@/lib/format/labels";

export default async function AdminWithdrawalsPage() {
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "reviewWithdrawals")) return <p>You do not have permission to review withdrawals.</p>;
  const { data, error } = await supabase.from("withdrawal_requests").select("id, reference, user_id, requested_amount_cents, payout_amount_cents, fee_amount_cents, status, destination_address, asset_symbol_snapshot, network_name_snapshot, created_at").order("created_at", { ascending: false }).limit(100);
  return (
    <div>
      <PageIntro title="Withdrawals" body="Mark a withdrawal complete only after the payout itself is confirmed. Rejecting or failing a request releases the reservation." />
      {error ? <p className="text-sm text-danger">Withdrawals could not be loaded.</p> : null}
      <div className="space-y-4">
        {(data ?? []).map((row) => (
          <article key={row.id} className="rounded-card border border-line bg-white p-4">
            <h2 className="font-medium">{row.reference}</h2>
            <p className="mt-1 text-sm text-ink-muted">{labelFor(withdrawalStatusLabel, row.status)} · <Money cents={row.requested_amount_cents} /> requested · payout {row.payout_amount_cents ? <Money cents={row.payout_amount_cents} /> : "—"} · fee {row.fee_amount_cents ? <Money cents={row.fee_amount_cents} /> : "—"}</p>
            <p className="mt-1 break-all font-mono text-xs">{row.asset_symbol_snapshot} · {row.network_name_snapshot} · {row.destination_address}</p>
            {["completed", "rejected", "cancelled", "failed"].includes(row.status) ? null : (
              <div className="mt-3">
                <StateForm action={reviewWithdrawalAction} submitLabel="Save decision">
                  <input type="hidden" name="withdrawalId" value={row.id} />
                  <Label htmlFor={`decision-${row.id}`}>Decision</Label>
                  <Select id={`decision-${row.id}`} name="decision" defaultValue="review">
                    <option value="review">Mark under review</option>
                    <option value="approve">Approve</option>
                    <option value="processing">Mark processing</option>
                    <option value="complete">Complete payout</option>
                    <option value="reject">Reject and release funds</option>
                    <option value="fail">Fail and release funds</option>
                  </Select>
                  <Label htmlFor={`hash-${row.id}`}>Payout transaction hash</Label>
                  <Input id={`hash-${row.id}`} name="payoutHash" className="font-mono" />
                  <Label htmlFor={`reason-${row.id}`}>Reason</Label>
                  <Textarea id={`reason-${row.id}`} name="reason" required />
                </StateForm>
              </div>
            )}
          </article>
        ))}
      </div>
    </div>
  );
}
