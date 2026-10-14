import { StatusBadge } from "@/components/ui/badge";
import { EmptyState, Money, PageIntro } from "@/components/ui/page";
import { requireUser } from "@/lib/auth/session";
import { formatTimestamp } from "@/lib/format/date";
import { categoryLabel, labelFor } from "@/lib/format/labels";

export default async function ActivityPage() {
  const { supabase, user } = await requireUser();
  const { data, error } = await supabase
    .from("investment_records")
    .select("id, activity_reference, category, description, execution_reference, amount_allocated_cents, status, recorded_at, realized_result_cents")
    .eq("user_id", user.id)
    .order("recorded_at", { ascending: false });

  return (
    <div>
      <PageIntro title="Investment activity" body="These are records entered by Aztek. They are not trading instructions and they are not deposits." />
      {error ? <p className="text-sm text-danger">Activity could not be loaded.</p> : null}
      {!error && (data ?? []).length === 0 ? (
        <EmptyState title="No investment activity" body="There is no recorded investment activity to display yet." />
      ) : (
        <div className="space-y-3">
          {(data ?? []).map((row) => (
            <article key={row.id} className="rounded-card border border-line bg-white p-5">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <h2 className="text-base font-medium">{labelFor(categoryLabel, row.category)}</h2>
                <StatusBadge status={row.status} label={row.status} />
              </div>
              <p className="mt-2 text-sm leading-6 text-ink-muted">{row.description}</p>
              <dl className="mt-3 grid gap-2 text-sm md:grid-cols-2">
                <div>Reference <span className="font-mono">{row.activity_reference}</span></div>
                <div>Execution reference <span className="font-mono">{row.execution_reference}</span></div>
                <div>Allocated <Money cents={row.amount_allocated_cents} /></div>
                <div>Realized {row.realized_result_cents === null ? "—" : <Money cents={row.realized_result_cents} />}</div>
                <div className="text-ink-muted">Updated {formatTimestamp(row.recorded_at)}</div>
              </dl>
            </article>
          ))}
        </div>
      )}
    </div>
  );
}
