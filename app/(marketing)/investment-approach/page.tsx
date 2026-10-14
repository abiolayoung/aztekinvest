import type { Metadata } from "next";

export const metadata: Metadata = { title: "Investment approach" };

export default function InvestmentApproachPage() {
  return (
    <main className="mx-auto max-w-3xl px-5 py-14">
      <h1 className="text-3xl font-medium tracking-tight">Investment approach</h1>
      <div className="mt-6 space-y-4 text-sm leading-7 text-ink-muted">
        <p>
          Aztek investment work is organized around research, diversification, risk awareness, portfolio oversight, and long-term planning. The descriptions below explain how activity may be recorded. They are not live trading positions, product offers, or forecasts.
        </p>
        <p>
          An allocation is recorded only when authorized personnel enter an actual execution reference and evidence reference. The cash used for that allocation leaves confirmed cash and becomes a holding at cost. Later market values are recorded separately. Until a verified valuation exists, performance is shown as not yet available.
        </p>
        <p>
          Categories that may appear on an account, when they correspond to a real recorded activity, include digital asset trading, currency market operations, diversified strategies, and private business investments. A category is not shown as active merely because it can be described.
        </p>
        <p>
          Clients can read their own portfolio and the activity Aztek has chosen to disclose. They cannot create executions, change valuations, or send trading instructions through this portal. Confidential counterparties, trading credentials, and proprietary methods are not displayed.
        </p>
        <p className="rounded-card border border-line bg-white p-4 text-ink">
          Investment values can fall. Past activity is not a promise of future results. No capital protection or fixed return is offered.
        </p>
      </div>
    </main>
  );
}
