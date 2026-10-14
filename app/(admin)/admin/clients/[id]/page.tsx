import { notFound } from "next/navigation";
import { accountStatusAction, adjustmentAction, verificationAction } from "@/lib/actions/admin";
import { StateForm } from "@/components/forms/state-form";
import { Input, Label, Select, Textarea } from "@/components/ui/fields";
import { Money, PageIntro } from "@/components/ui/page";
import { can } from "@/lib/auth/permissions";
import { requireUser } from "@/lib/auth/session";
import { mapSummary } from "@/lib/data/summary";
import { findPlan, totalPercent } from "@/lib/plans";

export default async function ClientDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "viewClients")) return <p>You do not have permission to view clients.</p>;
  const { data: client } = await supabase.from("profiles").select("*").eq("id", id).eq("role", "client").maybeSingle();
  if (!client) notFound();
  const plan = findPlan(client.selected_plan);
  const summaryResult = await supabase.rpc("get_account_summary", { target_user: client.id });
  const summaryRow = Array.isArray(summaryResult.data) ? summaryResult.data[0] : summaryResult.data;
  const summary = summaryRow ? mapSummary(summaryRow) : null;
  const [deposits, withdrawals] = await Promise.all([
    supabase.from("deposit_requests").select("id, reference, status, requested_amount_cents").eq("user_id", client.id).order("created_at", { ascending: false }).limit(8),
    supabase.from("withdrawal_requests").select("id, reference, status, requested_amount_cents").eq("user_id", client.id).order("created_at", { ascending: false }).limit(8),
  ]);

  return (
    <div>
      <PageIntro title={client.full_name || "Client"} body={`${client.verification_status} · ${client.account_status}`} />
      <p className="mb-4 text-sm">
        Plan:{" "}
        {plan ? (
          <span className="font-medium">
            {plan.name} ({totalPercent(plan)}% in {plan.durationDays} days)
          </span>
        ) : (
          <span className="text-ink-muted">Not selected</span>
        )}
        {" · "}Phone:{" "}
        {client.phone ? (
          <a href={`tel:${client.phone.replace(/[^\d+]/g, "")}`} className="font-medium text-brand hover:underline">
            {client.phone}
          </a>
        ) : (
          <span className="text-ink-muted">Not provided</span>
        )}
      </p>
      {summary ? (
        <p className="mb-4 text-sm">Cash <Money cents={summary.cashCents} /> · Reserved <Money cents={summary.reservedCents} /> · Holdings <Money cents={summary.holdingsValueCents} /> · Confirmed deposits <Money cents={summary.confirmedDepositsCents} /></p>
      ) : <p className="mb-4 text-sm text-danger">Balances could not be loaded.</p>}
      <div className="grid gap-4 lg:grid-cols-2">
        {can(profile.role, "reviewVerification") ? (
          <section className="rounded-card border border-line bg-white p-4">
            <h2 className="mb-3 font-medium">Verification</h2>
            <StateForm action={verificationAction} submitLabel="Save verification">
              <input type="hidden" name="userId" value={client.id} />
              <Select name="status" defaultValue="verified">
                <option value="verified">Approve</option>
                <option value="rejected">Reject</option>
                <option value="pending_review">Keep pending</option>
              </Select>
              <Textarea name="reason" placeholder="Reason" required />
            </StateForm>
          </section>
        ) : null}
        {can(profile.role, "manageClients") ? (
          <section className="rounded-card border border-line bg-white p-4">
            <h2 className="mb-3 font-medium">Account status</h2>
            <StateForm action={accountStatusAction} submitLabel="Update status">
              <input type="hidden" name="userId" value={client.id} />
              <Select name="status" defaultValue={client.account_status}>
                <option value="pending">Pending</option>
                <option value="active">Active</option>
                <option value="restricted">Restricted</option>
                <option value="suspended">Suspended</option>
                <option value="closed">Closed</option>
              </Select>
              <Textarea name="reason" placeholder="Reason" required />
            </StateForm>
          </section>
        ) : null}
      </div>
      {can(profile.role, "postAdjustments") ? (
        <section className="mt-4 rounded-card border border-line bg-white p-4">
          <h2 className="font-medium">Compensating cash adjustment</h2>
          <p className="mt-1 text-sm text-ink-muted">This posts a new ledger entry. It does not erase a deposit or withdrawal.</p>
          <div className="mt-3">
            <StateForm action={adjustmentAction} submitLabel="Post adjustment">
              <input type="hidden" name="userId" value={client.id} />
              <Label htmlFor="direction">Direction</Label>
              <Select id="direction" name="direction" defaultValue="credit">
                <option value="credit">Credit client cash</option>
                <option value="debit">Debit client cash</option>
              </Select>
              <Label htmlFor="amount">Amount</Label>
              <Input id="amount" name="amount" required />
              <Label htmlFor="description">Client-facing description</Label>
              <Input id="description" name="description" required />
              <Label htmlFor="reason">Internal reason</Label>
              <Textarea id="reason" name="reason" required />
              <Label htmlFor="evidenceReference">Evidence reference</Label>
              <Input id="evidenceReference" name="evidenceReference" required />
            </StateForm>
          </div>
        </section>
      ) : null}
      <div className="mt-6 grid gap-4 md:grid-cols-2 text-sm">
        <List title="Deposits" rows={(deposits.data ?? []).map((item) => `${item.reference} · ${item.status}`)} />
        <List title="Withdrawals" rows={(withdrawals.data ?? []).map((item) => `${item.reference} · ${item.status}`)} />
      </div>
    </div>
  );
}

function List({ title, rows }: { title: string; rows: string[] }) {
  return (
    <section className="rounded-card border border-line bg-white p-4">
      <h2 className="font-medium">{title}</h2>
      {rows.length === 0 ? <p className="mt-2 text-ink-muted">None recorded.</p> : <ul className="mt-2 space-y-1">{rows.map((row) => <li key={row}>{row}</li>)}</ul>}
    </section>
  );
}
