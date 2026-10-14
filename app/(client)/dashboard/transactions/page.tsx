import Link from "next/link";
import { EmptyState, PageIntro } from "@/components/ui/page";
import { requireUser } from "@/lib/auth/session";
import { formatTimestamp } from "@/lib/format/date";
import { labelFor, ledgerTypeLabel } from "@/lib/format/labels";

export default async function TransactionsPage() {
  const { supabase } = await requireUser();
  const { data, error } = await supabase
    .from("ledger_transactions")
    .select("id, reference, transaction_type, description, created_at")
    .order("created_at", { ascending: false })
    .limit(100);

  return (
    <div>
      <div className="mb-6 flex items-end justify-between gap-3">
        <PageIntro title="Transactions" body="Posted ledger activity for this account. Pending deposits are not listed as credits." />
        <Link href="/api/statements" className="text-sm text-brand">Download CSV</Link>
      </div>
      {error ? <p className="text-sm text-danger">Transactions could not be loaded.</p> : null}
      {!error && (data ?? []).length === 0 ? (
        <EmptyState title="No transactions" body="Your account activity will appear here as transactions are recorded." />
      ) : (
        <div className="overflow-x-auto rounded-card border border-line bg-white">
          <table className="w-full min-w-[680px] text-sm">
            <thead className="border-b border-line text-left text-xs text-ink-muted">
              <tr>
                <th className="px-4 py-3 font-medium">When</th>
                <th className="px-4 py-3 font-medium">Reference</th>
                <th className="px-4 py-3 font-medium">Type</th>
                <th className="px-4 py-3 font-medium">Description</th>
              </tr>
            </thead>
            <tbody>
              {(data ?? []).map((row) => (
                <tr key={row.id} className="border-b border-line">
                  <td className="px-4 py-3 text-ink-muted">{formatTimestamp(row.created_at)}</td>
                  <td className="px-4 py-3 font-mono text-xs">{row.reference}</td>
                  <td className="px-4 py-3">{labelFor(ledgerTypeLabel, row.transaction_type)}</td>
                  <td className="px-4 py-3">{row.description}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
