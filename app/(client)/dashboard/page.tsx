import Link from "next/link";
import { PerformancePanel } from "@/components/portfolio/performance-panel";
import { Card, CardBody } from "@/components/ui/card";
import { EmptyState, Money, PageIntro } from "@/components/ui/page";
import { StatusBadge } from "@/components/ui/badge";
import { requireUser } from "@/lib/auth/session";
import { mapSummary, type AccountSummary } from "@/lib/data/summary";
import { formatTimestamp } from "@/lib/format/date";
import { categoryLabel, labelFor, ledgerTypeLabel } from "@/lib/format/labels";
import { toCents } from "@/lib/finance/money";
import type { ExternalFlow, PerformancePoint } from "@/lib/finance/performance";

export default async function DashboardPage() {
  const { supabase, user, profile } = await requireUser();
  await supabase.rpc("expire_my_stale_deposits");
  const summaryResult = await supabase.rpc("get_account_summary", { target_user: user.id });
  const summaryRow = Array.isArray(summaryResult.data) ? summaryResult.data[0] : summaryResult.data;
  const summary = summaryRow ? mapSummary(summaryRow) : null;

  const [transactions, activity, valuations, deposits, withdrawals] = await Promise.all([
    supabase.from("ledger_transactions").select("id, reference, transaction_type, description, created_at").order("created_at", { ascending: false }).limit(6),
    supabase.from("investment_records").select("id, activity_reference, category, description, status, recorded_at").eq("user_id", user.id).order("recorded_at", { ascending: false }).limit(5),
    supabase.from("portfolio_valuations").select("valuation_timestamp, total_account_value_cents, valuation_source").eq("user_id", user.id).order("valuation_timestamp", { ascending: true }),
    supabase.from("deposit_requests").select("credited_at, credited_amount_cents").eq("user_id", user.id).eq("status", "credited"),
    supabase.from("withdrawal_requests").select("processed_at, requested_amount_cents").eq("user_id", user.id).eq("status", "completed"),
  ]);

  if (summaryResult.error || !summary) {
    return (
      <div role="alert" className="rounded-card border border-red-200 bg-white p-5 text-sm text-danger">
        We could not load your account records. Nothing below should be read as a balance.
      </div>
    );
  }

  const points: PerformancePoint[] = (valuations.data ?? []).map((row) => ({
    at: row.valuation_timestamp,
    totalCents: toCents(row.total_account_value_cents),
    source: row.valuation_source,
  }));
  const flows: ExternalFlow[] = [
    ...(deposits.data ?? []).filter((row) => row.credited_at).map((row) => ({
      at: row.credited_at as string,
      cents: toCents(row.credited_amount_cents),
    })),
    ...(withdrawals.data ?? []).filter((row) => row.processed_at).map((row) => ({
      at: row.processed_at as string,
      cents: -toCents(row.requested_amount_cents),
    })),
  ];
  const funded = summary.cashCents > 0n || summary.confirmedDepositsCents > 0n || summary.activeHoldings > 0;
  const hasWelcomeBonus = (transactions.data ?? []).some((row) => row.transaction_type === "signup_bonus");

  return (
    <div>
      <div className="mb-6 flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-medium">Welcome back{profile.full_name ? `, ${profile.full_name.split(" ")[0]}` : ""}</h1>
          <p className="mt-1 text-sm text-ink-muted">Here is an overview of your managed account.</p>
        </div>
        <div className="flex gap-2">
          <Link href="/dashboard/deposit" className="rounded-lg bg-brand px-4 py-2.5 text-sm text-white">Make a deposit</Link>
          <Link href="/dashboard/portfolio" className="rounded-lg border border-line bg-white px-4 py-2.5 text-sm">View portfolio</Link>
        </div>
      </div>
      {hasWelcomeBonus ? (
        <div className="mb-6 rounded-card border border-line bg-white px-4 py-3 text-sm">
          Your <span className="font-medium">$100.00 welcome bonus</span> is included in available cash. Deposits still require administrator verification before they are credited.
        </div>
      ) : null}
      {!funded ? (
        <div className="mb-6">
          <EmptyState
            title="Your account is ready."
            body="Make your first deposit to begin funding your managed account."
            action={<Link href="/dashboard/deposit" className="text-sm text-brand">Make a deposit</Link>}
          />
        </div>
      ) : null}
      <section className="grid gap-3 md:grid-cols-4">
        <SummaryCard label="Total account value" value={<Money cents={summary.totalAccountValueCents} />} detail={summary.valuationComplete ? "Confirmed cash plus recorded holding values." : "Some holdings are awaiting a valuation and are excluded."} />
        <SummaryCard label="Confirmed deposits" value={<Money cents={summary.confirmedDepositsCents} />} detail="Credited deposits only. This is not the current account value." />
        <SummaryCard label="Currently invested" value={<Money cents={summary.holdingsValueCents} />} detail={investedDetail(summary)} />
        <SummaryCard label="Available cash" value={<Money cents={summary.cashCents} />} detail={summary.reservedCents > 0n ? "Reserved withdrawal funds are excluded." : "Pending deposits are not included."} />
      </section>
      {summary.pendingDepositsCents > 0n ? (
        <p className="mt-3 text-sm text-ink-muted">Pending deposit requests of <Money cents={summary.pendingDepositsCents} /> are not included in the account value.</p>
      ) : null}
      <div className="mt-6 grid gap-4 lg:grid-cols-[1.4fr_0.8fr]">
        <Card>
          <CardBody>
            <PerformancePanel points={points} flows={flows} />
          </CardBody>
        </Card>
        <Card>
          <CardBody>
            <h2 className="text-sm font-medium">Account status</h2>
            <dl className="mt-3 space-y-2 text-sm">
              <StatusRow label="Verification" value={profile.verification_status === "verified" ? "Approved" : "Incomplete"} />
              <StatusRow label="Email" value={profile.email_verified_at ? "Verified" : "Not verified"} />
              <StatusRow label="Deposits" value={profile.verification_status === "verified" && profile.account_status === "active" ? "Subject to funding settings" : "Unavailable"} />
            </dl>
          </CardBody>
        </Card>
      </div>
      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Card>
          <CardBody>
            <h2 className="text-sm font-medium">Recent transactions</h2>
            {transactions.error ? <p className="mt-3 text-sm text-danger">Transactions could not be loaded.</p> : null}
            {!transactions.error && (transactions.data ?? []).length === 0 ? (
              <p className="mt-3 text-sm text-ink-muted">Your account activity will appear here as transactions are recorded.</p>
            ) : (
              <ul className="mt-3 divide-y divide-line">
                {(transactions.data ?? []).map((row) => (
                  <li key={row.id} className="flex items-center justify-between gap-3 py-3 text-sm">
                    <span>
                      <span className="block">{labelFor(ledgerTypeLabel, row.transaction_type)}</span>
                      <span className="text-xs text-ink-muted">{row.reference} · {formatTimestamp(row.created_at)}</span>
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </CardBody>
        </Card>
        <Card>
          <CardBody>
            <h2 className="text-sm font-medium">Managed investment activity</h2>
            {(activity.data ?? []).length === 0 ? (
              <p className="mt-3 text-sm text-ink-muted">There is no recorded investment activity to display yet.</p>
            ) : (
              <ul className="mt-3 divide-y divide-line">
                {(activity.data ?? []).map((row) => (
                  <li key={row.id} className="flex items-center justify-between gap-3 py-3 text-sm">
                    <span>
                      <span className="block">{labelFor(categoryLabel, row.category)}</span>
                      <span className="text-xs text-ink-muted">{row.activity_reference}</span>
                    </span>
                    <StatusBadge status={row.status} label={row.status} />
                  </li>
                ))}
              </ul>
            )}
          </CardBody>
        </Card>
      </div>
    </div>
  );
}

function investedDetail(summary: AccountSummary): string {
  if (summary.activeHoldings === 0) return "No holdings recorded.";
  if (!summary.hasVerifiedValuation) return "Recorded at allocation cost until a market valuation is recorded.";
  return "Latest recorded holding value. This is not the amount deposited.";
}

function SummaryCard({ label, value, detail }: { label: string; value: React.ReactNode; detail: string }) {
  return (
    <Card>
      <CardBody>
        <p className="text-xs text-ink-muted">{label}</p>
        <p className="mt-2 text-xl font-medium">{value}</p>
        <p className="mt-2 text-xs leading-5 text-ink-muted">{detail}</p>
      </CardBody>
    </Card>
  );
}

function StatusRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-3">
      <dt className="text-ink-muted">{label}</dt>
      <dd>{value}</dd>
    </div>
  );
}
