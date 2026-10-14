import { Money, PageIntro } from "@/components/ui/page";
import { can } from "@/lib/auth/permissions";
import { requireUser } from "@/lib/auth/session";
import { formatTimestamp } from "@/lib/format/date";
import { categoryLabel, labelFor } from "@/lib/format/labels";

export default async function InvestmentsPage() {
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "viewLedger")) return <p>You do not have permission to view investment records.</p>;
  const { data, error } = await supabase.from("investment_records").select("id, user_id, activity_reference, category, description, amount_allocated_cents, status, recorded_at, evidence_reference").order("recorded_at", { ascending: false }).limit(100);
  return (
    <div>
      <PageIntro title="Investment activity records" body="Broker-managed records are separate from client funding transactions." />
      {error ? <p className="text-sm text-danger">Records could not be loaded.</p> : null}
      <div className="space-y-3">
        {(data ?? []).map((row) => (
          <article key={row.id} className="rounded-card border border-line bg-white p-4 text-sm">
            <div className="flex justify-between gap-3"><h2 className="font-medium">{row.activity_reference}</h2><span>{row.status}</span></div>
            <p className="mt-1">{labelFor(categoryLabel, row.category)} · <Money cents={row.amount_allocated_cents} /></p>
            <p className="mt-1 text-ink-muted">{row.description}</p>
            <p className="mt-1 text-xs text-ink-muted">Evidence {row.evidence_reference} · {formatTimestamp(row.recorded_at)}</p>
          </article>
        ))}
      </div>
    </div>
  );
}
