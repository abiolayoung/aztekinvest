import { Money, PageIntro } from "@/components/ui/page";
import { can } from "@/lib/auth/permissions";
import { requireUser } from "@/lib/auth/session";

export default async function AdminHomePage() {
  const { supabase, profile } = await requireUser();
  const { data, error } = await supabase.rpc("get_admin_overview");
  const overview = (data ?? {}) as Record<string, number>;
  const reconciliation = can(profile.role, "manageInvestments") || can(profile.role, "postAdjustments")
    ? await supabase.rpc("get_ledger_reconciliation")
    : null;
  const books = Array.isArray(reconciliation?.data) ? reconciliation.data[0] : null;

  return (
    <div>
      <PageIntro title="Operations overview" body="Counts come from account records. They are not performance claims." />
      {error ? <p className="text-sm text-danger">The overview could not be loaded.</p> : (
        <div className="grid gap-3 md:grid-cols-3">
          {[
            ["Clients", overview.clients],
            ["Awaiting verification", overview.awaiting_verification],
            ["Open deposit requests", overview.pending_deposits],
            ["Deposits under review", overview.deposits_under_review],
            ["Open withdrawals", overview.pending_withdrawals],
            ["Open support", overview.open_support],
          ].map(([label, value]) => (
            <div key={String(label)} className="rounded-card border border-line bg-white p-4">
              <p className="text-xs text-ink-muted">{label}</p>
              <p className="numeric mt-2 text-2xl">{value ?? "—"}</p>
            </div>
          ))}
        </div>
      )}
      {books ? (
        <div className="mt-6 rounded-card border border-line bg-white p-5 text-sm">
          <h2 className="font-medium">Ledger reconciliation</h2>
          <p className="mt-1 text-ink-muted">Company assets should equal client liabilities plus fee revenue. A non-zero break needs investigation. Unrealized valuations are not part of this cash equation.</p>
          <dl className="mt-4 grid gap-2 md:grid-cols-2">
            <div>Custody cash <Money cents={books.custody_cash_cents} /></div>
            <div>Invested assets at cost <Money cents={books.invested_assets_cents} /></div>
            <div>Client liabilities <Money cents={books.client_liabilities_cents} /></div>
            <div>Fee revenue <Money cents={books.fee_revenue_cents} /></div>
            <div>Break <Money cents={books.break_cents} /></div>
          </dl>
        </div>
      ) : null}
    </div>
  );
}
