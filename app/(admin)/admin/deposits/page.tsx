import Link from "next/link";
import { StatusBadge } from "@/components/ui/badge";
import { Money, PageIntro } from "@/components/ui/page";
import { can } from "@/lib/auth/permissions";
import { requireUser } from "@/lib/auth/session";
import { formatTimestamp } from "@/lib/format/date";
import { depositStatusLabel, labelFor } from "@/lib/format/labels";

const filters = ["awaiting_payment", "payment_detected", "confirming", "under_review", "credited", "rejected"];

export default async function AdminDepositsPage({ searchParams }: { searchParams: Promise<{ status?: string }> }) {
  const { status } = await searchParams;
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "reviewDeposits")) return <p>You do not have permission to review deposits.</p>;
  let query = supabase.from("deposit_requests").select("id, reference, user_id, requested_amount_cents, asset_symbol_snapshot, network_name_snapshot, observed_crypto_amount, transaction_hash, confirmation_count, status, created_at, payment_declared_at, receipt_file_name").order("created_at", { ascending: false }).limit(100);
  if (status && filters.includes(status)) query = query.eq("status", status);
  const { data, error } = await query;
  const ids = [...new Set((data ?? []).map((row) => row.user_id))];
  const { data: profiles } = ids.length ? await supabase.from("profiles").select("id, full_name").in("id", ids) : { data: [] };
  const names = new Map((profiles ?? []).map((item) => [item.id, item.full_name]));

  return (
    <div>
      <PageIntro
        title="Deposit review"
        body="Open deposits with receipts, verify the upload, then press Received to credit the client dashboard."
      />
      <div className="mb-4 flex flex-wrap gap-2 text-sm">
        <Link href="/admin/deposits" className="rounded-lg bg-muted px-2 py-1">All</Link>
        {filters.map((item) => (
          <Link key={item} href={`/admin/deposits?status=${item}`} className="rounded-lg bg-muted px-2 py-1">{labelFor(depositStatusLabel, item)}</Link>
        ))}
      </div>
      {error ? <p className="text-sm text-danger">The queue could not be loaded.</p> : null}
      <div className="overflow-x-auto rounded-card border border-line bg-white">
        <table className="w-full min-w-[980px] text-sm">
          <thead className="border-b border-line text-left text-xs text-ink-muted">
            <tr>
              {["Reference", "Client", "Requested", "Asset", "Network", "Receipt", "Hash", "Marked paid", "Submitted", "Status"].map((heading) => (
                <th key={heading} className="px-3 py-3 font-medium">{heading}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {(data ?? []).map((row) => (
              <tr key={row.id} className="border-b border-line">
                <td className="px-3 py-3"><Link className="text-brand" href={`/admin/deposits/${row.id}`}>{row.reference}</Link></td>
                <td className="px-3 py-3">{names.get(row.user_id) || "Client"}</td>
                <td className="px-3 py-3 text-right"><Money cents={row.requested_amount_cents} /></td>
                <td className="px-3 py-3">{row.asset_symbol_snapshot}</td>
                <td className="px-3 py-3">{row.network_name_snapshot}</td>
                <td className="px-3 py-3">{row.receipt_file_name ?? "—"}</td>
                <td className="px-3 py-3 font-mono text-xs">{row.transaction_hash ? `${row.transaction_hash.slice(0, 10)}…` : "—"}</td>
                <td className="px-3 py-3">{row.payment_declared_at ? formatTimestamp(row.payment_declared_at) : "—"}</td>
                <td className="px-3 py-3">{formatTimestamp(row.created_at)}</td>
                <td className="px-3 py-3"><StatusBadge status={row.status} label={labelFor(depositStatusLabel, row.status)} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
