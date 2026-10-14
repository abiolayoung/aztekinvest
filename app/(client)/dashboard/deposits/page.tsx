import Link from "next/link";
import { StatusBadge } from "@/components/ui/badge";
import { EmptyState, Money, PageIntro } from "@/components/ui/page";
import { requireUser } from "@/lib/auth/session";
import { formatTimestamp } from "@/lib/format/date";
import { depositStatusLabel, labelFor } from "@/lib/format/labels";

export default async function DepositsPage() {
  const { supabase, user } = await requireUser();
  await supabase.rpc("expire_my_stale_deposits");
  const { data, error } = await supabase
    .from("deposit_requests")
    .select("id, reference, requested_amount_cents, credited_amount_cents, asset_symbol_snapshot, network_name_snapshot, status, created_at")
    .eq("user_id", user.id)
    .order("created_at", { ascending: false });

  return (
    <div>
      <PageIntro title="Deposit history" body="Pending requests are listed here. They do not increase your confirmed balance." />
      {error ? <p role="alert" className="text-sm text-danger">Deposit history could not be loaded.</p> : null}
      {!error && (data ?? []).length === 0 ? (
        <EmptyState title="No deposit requests" body="Your account is ready. Make your first deposit to begin funding your managed account." action={<Link className="text-sm text-brand" href="/dashboard/deposit">Make a deposit</Link>} />
      ) : (
        <div className="overflow-x-auto rounded-card border border-line bg-white">
          <table className="w-full min-w-[720px] text-left text-sm">
            <thead className="border-b border-line text-xs text-ink-muted">
              <tr>
                <th className="px-4 py-3 font-medium">Reference</th>
                <th className="px-4 py-3 text-right font-medium">Requested</th>
                <th className="px-4 py-3 text-right font-medium">Credited</th>
                <th className="px-4 py-3 font-medium">Asset</th>
                <th className="px-4 py-3 font-medium">Status</th>
                <th className="px-4 py-3 font-medium">Created</th>
              </tr>
            </thead>
            <tbody>
              {(data ?? []).map((row) => (
                <tr key={row.id} className="border-b border-line last:border-0">
                  <td className="px-4 py-3"><Link className="text-brand" href={`/dashboard/deposits/${row.id}`}>{row.reference}</Link></td>
                  <td className="px-4 py-3 text-right"><Money cents={row.requested_amount_cents} /></td>
                  <td className="px-4 py-3 text-right">{row.credited_amount_cents ? <Money cents={row.credited_amount_cents} /> : "—"}</td>
                  <td className="px-4 py-3">{row.asset_symbol_snapshot} · {row.network_name_snapshot}</td>
                  <td className="px-4 py-3"><StatusBadge status={row.status} label={labelFor(depositStatusLabel, row.status)} /></td>
                  <td className="px-4 py-3 text-ink-muted">{formatTimestamp(row.created_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
