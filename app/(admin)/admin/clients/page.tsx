import Link from "next/link";
import { PageIntro } from "@/components/ui/page";
import { StatusBadge } from "@/components/ui/badge";
import { can } from "@/lib/auth/permissions";
import { requireUser } from "@/lib/auth/session";
import { accountStatusLabel, labelFor, verificationLabel } from "@/lib/format/labels";

export default async function ClientsPage({ searchParams }: { searchParams: Promise<{ q?: string }> }) {
  const { q } = await searchParams;
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "viewClients")) return <p>You do not have permission to view clients.</p>;
  let query = supabase.from("profiles").select("id, full_name, country_code, verification_status, account_status, created_at").eq("role", "client").order("created_at", { ascending: false }).limit(100);
  if (q) query = query.ilike("full_name", `%${q.replace(/[%_]/g, "")}%`);
  const { data, error } = await query;
  return (
    <div>
      <PageIntro title="Clients" body="Search by name. Financial history is not edited from this list." />
      <form className="mb-4">
        <input name="q" defaultValue={q ?? ""} placeholder="Search name" className="h-11 w-full max-w-sm rounded-lg border border-line px-3 text-sm" />
      </form>
      {error ? <p className="text-sm text-danger">Clients could not be loaded.</p> : null}
      <div className="overflow-x-auto rounded-card border border-line bg-white">
        <table className="w-full text-sm">
          <thead className="border-b border-line text-left text-xs text-ink-muted">
            <tr><th className="px-4 py-3">Name</th><th className="px-4 py-3">Country</th><th className="px-4 py-3">Verification</th><th className="px-4 py-3">Status</th></tr>
          </thead>
          <tbody>
            {(data ?? []).map((client) => (
              <tr key={client.id} className="border-b border-line">
                <td className="px-4 py-3"><Link className="text-brand" href={`/admin/clients/${client.id}`}>{client.full_name || "Unnamed client"}</Link></td>
                <td className="px-4 py-3">{client.country_code ?? "—"}</td>
                <td className="px-4 py-3"><StatusBadge status={client.verification_status} label={labelFor(verificationLabel, client.verification_status)} /></td>
                <td className="px-4 py-3"><StatusBadge status={client.account_status} label={labelFor(accountStatusLabel, client.account_status)} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
