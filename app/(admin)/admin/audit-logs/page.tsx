import { PageIntro } from "@/components/ui/page";
import { can } from "@/lib/auth/permissions";
import { requireUser } from "@/lib/auth/session";
import { formatTimestamp } from "@/lib/format/date";

export default async function AuditPage() {
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "viewAudit")) return <p>You do not have permission to view audit logs.</p>;
  const { data, error } = await supabase.from("audit_logs").select("id, action, entity_type, entity_id, reason, created_at").order("created_at", { ascending: false }).limit(150);
  return (
    <div>
      <PageIntro title="Audit logs" body="Sensitive financial decisions are appended here. Entries cannot be edited." />
      {error ? <p className="text-sm text-danger">Audit logs could not be loaded.</p> : null}
      <div className="overflow-x-auto rounded-card border border-line bg-white">
        <table className="w-full min-w-[760px] text-sm">
          <thead className="border-b border-line text-left text-xs text-ink-muted">
            <tr><th className="px-4 py-3">When</th><th className="px-4 py-3">Action</th><th className="px-4 py-3">Record</th><th className="px-4 py-3">Reason</th></tr>
          </thead>
          <tbody>
            {(data ?? []).map((row) => (
              <tr key={row.id} className="border-b border-line">
                <td className="px-4 py-3">{formatTimestamp(row.created_at)}</td>
                <td className="px-4 py-3">{row.action}</td>
                <td className="px-4 py-3">{row.entity_type}</td>
                <td className="px-4 py-3">{row.reason ?? "—"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
