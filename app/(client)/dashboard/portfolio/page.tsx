import { PerformancePanel } from "@/components/portfolio/performance-panel";
import { Card, CardBody } from "@/components/ui/card";
import { EmptyState, Money, PageIntro } from "@/components/ui/page";
import { requireUser } from "@/lib/auth/session";
import { mapSummary } from "@/lib/data/summary";
import { formatTimestamp } from "@/lib/format/date";
import { categoryLabel, labelFor } from "@/lib/format/labels";
import { toCents } from "@/lib/finance/money";
import { unrealizedResult } from "@/lib/finance/accounting";
import type { ExternalFlow, PerformancePoint } from "@/lib/finance/performance";

export default async function PortfolioPage() {
  const { supabase, user } = await requireUser();
  const summaryResult = await supabase.rpc("get_account_summary", { target_user: user.id });
  const row = Array.isArray(summaryResult.data) ? summaryResult.data[0] : summaryResult.data;
  const summary = row ? mapSummary(row) : null;
  const [holdings, valuations, deposits, withdrawals] = await Promise.all([
    supabase.from("portfolio_holdings").select("id, category, cost_basis_cents, current_valuation_cents, valuation_source, valuation_timestamp, status, realized_result_cents").eq("user_id", user.id).order("created_at", { ascending: false }),
    supabase.from("portfolio_valuations").select("valuation_timestamp, total_account_value_cents, valuation_source").eq("user_id", user.id).order("valuation_timestamp", { ascending: true }),
    supabase.from("deposit_requests").select("credited_at, credited_amount_cents").eq("status", "credited"),
    supabase.from("withdrawal_requests").select("processed_at, requested_amount_cents").eq("status", "completed"),
  ]);
  if (!summary) return <p role="alert" className="text-sm text-danger">Portfolio records could not be loaded.</p>;

  const points: PerformancePoint[] = (valuations.data ?? []).map((item) => ({
    at: item.valuation_timestamp,
    totalCents: toCents(item.total_account_value_cents),
    source: item.valuation_source,
  }));
  const flows: ExternalFlow[] = [
    ...(deposits.data ?? []).filter((item) => item.credited_at).map((item) => ({ at: item.credited_at as string, cents: toCents(item.credited_amount_cents) })),
    ...(withdrawals.data ?? []).filter((item) => item.processed_at).map((item) => ({ at: item.processed_at as string, cents: -toCents(item.requested_amount_cents) })),
  ];

  return (
    <div>
      <PageIntro title="My portfolio" body="Values come from recorded holdings and valuations. This page cannot be used to trade." />
      <div className="mb-4 grid gap-3 md:grid-cols-3">
        <Card><CardBody><p className="text-xs text-ink-muted">Cash balance</p><p className="mt-2 text-xl"><Money cents={summary.cashCents} /></p></CardBody></Card>
        <Card><CardBody><p className="text-xs text-ink-muted">Holdings value</p><p className="mt-2 text-xl"><Money cents={summary.holdingsValueCents} /></p></CardBody></Card>
        <Card><CardBody><p className="text-xs text-ink-muted">Realized result</p><p className="mt-2 text-xl"><Money cents={summary.realizedPnlCents} /></p><p className="mt-1 text-xs text-ink-muted">From closed holdings only.</p></CardBody></Card>
      </div>
      <Card><CardBody><PerformancePanel points={points} flows={flows} /></CardBody></Card>
      <div className="mt-4">
        {(holdings.data ?? []).length === 0 ? (
          <EmptyState title="No portfolio valuations" body="Your portfolio valuation will appear here when verified investment records become available." />
        ) : (
          <div className="overflow-x-auto rounded-card border border-line bg-white">
            <table className="w-full min-w-[760px] text-sm">
              <thead className="border-b border-line text-left text-xs text-ink-muted">
                <tr>
                  <th className="px-4 py-3 font-medium">Category</th>
                  <th className="px-4 py-3 text-right font-medium">Cost</th>
                  <th className="px-4 py-3 text-right font-medium">Recorded value</th>
                  <th className="px-4 py-3 text-right font-medium">Unrealized</th>
                  <th className="px-4 py-3 font-medium">Source</th>
                </tr>
              </thead>
              <tbody>
                {(holdings.data ?? []).map((holding) => {
                  const unrealized = holding.status === "active"
                    ? unrealizedResult(holding.cost_basis_cents === null ? null : toCents(holding.cost_basis_cents), holding.current_valuation_cents === null ? null : toCents(holding.current_valuation_cents))
                    : holding.realized_result_cents === null ? null : toCents(holding.realized_result_cents);
                  return (
                    <tr key={holding.id} className="border-b border-line">
                      <td className="px-4 py-3">{labelFor(categoryLabel, holding.category)}</td>
                      <td className="px-4 py-3 text-right">{holding.cost_basis_cents === null ? "—" : <Money cents={holding.cost_basis_cents} />}</td>
                      <td className="px-4 py-3 text-right">{holding.current_valuation_cents === null ? "Awaiting valuation" : <Money cents={holding.current_valuation_cents} />}</td>
                      <td className="px-4 py-3 text-right">{unrealized === null ? "—" : <Money cents={unrealized} />}</td>
                      <td className="px-4 py-3 text-ink-muted">{holding.valuation_source === "verified_valuation" ? `Verified ${formatTimestamp(holding.valuation_timestamp)}` : holding.valuation_source === "allocation_at_cost" ? "Allocation cost" : holding.status}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
