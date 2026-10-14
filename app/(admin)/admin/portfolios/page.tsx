import { allocateAction, closeHoldingAction, feeAction, valuationAction } from "@/lib/actions/admin";
import { StateForm } from "@/components/forms/state-form";
import { Input, Label, Select, Textarea } from "@/components/ui/fields";
import { Money, PageIntro } from "@/components/ui/page";
import { can } from "@/lib/auth/permissions";
import { requireUser } from "@/lib/auth/session";
import { mapSummary } from "@/lib/data/summary";
import { categoryLabel, labelFor } from "@/lib/format/labels";

export default async function PortfoliosPage({ searchParams }: { searchParams: Promise<{ user?: string }> }) {
  const { user: selected } = await searchParams;
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "manageInvestments")) return <p>You do not have permission to record investments.</p>;
  const { data: clients } = await supabase.from("profiles").select("id, full_name").eq("role", "client").order("full_name").limit(200);
  const clientId = selected || clients?.[0]?.id;
  const summaryResult = clientId ? await supabase.rpc("get_account_summary", { target_user: clientId }) : { data: null };
  const summaryRow = Array.isArray(summaryResult.data) ? summaryResult.data[0] : summaryResult.data;
  const summary = summaryRow ? mapSummary(summaryRow) : null;
  const { data: holdings } = clientId
    ? await supabase.from("portfolio_holdings").select("id, category, status, cost_basis_cents, current_valuation_cents, valuation_source").eq("user_id", clientId).order("created_at", { ascending: false })
    : { data: [] };

  return (
    <div>
      <PageIntro title="Portfolio records" body="Record only activity that has an execution reference and evidence. An allocation moves cash to a holding at cost and does not create a gain." />
      <form className="mb-4">
        <Label htmlFor="user">Client</Label>
        <Select id="user" name="user" defaultValue={clientId}>
          {(clients ?? []).map((client) => <option key={client.id} value={client.id}>{client.full_name}</option>)}
        </Select>
        <button className="mt-2 text-sm text-brand" type="submit">Load client</button>
      </form>
      {summary ? <p className="mb-4 text-sm">Confirmed cash <Money cents={summary.cashCents} /> · Holdings <Money cents={summary.holdingsValueCents} /></p> : null}
      <div className="grid gap-4 lg:grid-cols-2">
        <section className="rounded-card border border-line bg-white p-4">
          <h2 className="mb-3 font-medium">Record allocation</h2>
          <StateForm action={allocateAction} submitLabel="Record allocation">
            <input type="hidden" name="userId" value={clientId ?? ""} />
            <Select name="category" defaultValue="diversified_strategies">
              {Object.entries(categoryLabel).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
            </Select>
            <Textarea name="description" placeholder="Client-facing description" required />
            <Input name="amount" placeholder="Amount in USD" required />
            <Input name="executionReference" placeholder="Execution reference" required />
            <Input name="evidenceReference" placeholder="Evidence reference" required />
            <Input name="executedAt" type="datetime-local" />
          </StateForm>
        </section>
        <section className="rounded-card border border-line bg-white p-4">
          <h2 className="mb-3 font-medium">Record fee</h2>
          <StateForm action={feeAction} submitLabel="Record fee">
            <input type="hidden" name="userId" value={clientId ?? ""} />
            <Input name="amount" placeholder="Fee amount" required />
            <Input name="description" placeholder="Client-facing description" required />
            <Input name="evidenceReference" placeholder="Evidence reference" required />
          </StateForm>
        </section>
      </div>
      <div className="mt-4 space-y-4">
        {(holdings ?? []).map((holding) => (
          <article key={holding.id} className="rounded-card border border-line bg-white p-4 text-sm">
            <p>{labelFor(categoryLabel, holding.category)} · {holding.status} · cost {holding.cost_basis_cents ? <Money cents={holding.cost_basis_cents} /> : "—"} · value {holding.current_valuation_cents ? <Money cents={holding.current_valuation_cents} /> : "Awaiting valuation"}</p>
            <p className="text-xs text-ink-muted">{holding.valuation_source}</p>
            {holding.status === "active" ? (
              <div className="mt-3 grid gap-4 md:grid-cols-2">
                <StateForm action={valuationAction} submitLabel="Record valuation">
                  <input type="hidden" name="holdingId" value={holding.id} />
                  <Label htmlFor={`value-${holding.id}`}>Verified value</Label>
                  <Input id={`value-${holding.id}`} name="valuation" required />
                  <Input name="evidenceReference" placeholder="Evidence reference" required />
                </StateForm>
                <StateForm action={closeHoldingAction} submitLabel="Close holding">
                  <input type="hidden" name="holdingId" value={holding.id} />
                  <Label htmlFor={`proceeds-${holding.id}`}>Proceeds</Label>
                  <Input id={`proceeds-${holding.id}`} name="proceeds" required />
                  <Input name="executionReference" placeholder="Execution reference" required />
                  <Input name="evidenceReference" placeholder="Evidence reference" required />
                </StateForm>
              </div>
            ) : null}
          </article>
        ))}
      </div>
    </div>
  );
}
