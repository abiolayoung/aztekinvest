import { markNotificationsReadAction } from "@/lib/actions/support";
import { EmptyState, PageIntro } from "@/components/ui/page";
import { requireUser } from "@/lib/auth/session";
import { formatTimestamp } from "@/lib/format/date";

export default async function NotificationsPage() {
  const { supabase, user } = await requireUser();
  const { data, error } = await supabase.from("notifications").select("id, title, message, created_at, read_at").eq("user_id", user.id).order("created_at", { ascending: false }).limit(50);
  return (
    <div>
      <div className="mb-6 flex items-end justify-between">
        <PageIntro title="Notifications" />
        <form action={markNotificationsReadAction}>
          <button className="text-sm text-brand" type="submit">Mark all read</button>
        </form>
      </div>
      {error ? <p className="text-sm text-danger">Notifications could not be loaded.</p> : null}
      {!error && (data ?? []).length === 0 ? <EmptyState title="No notifications" body="Deposit, withdrawal, and account notices will appear here." /> : null}
      <div className="space-y-3">
        {(data ?? []).map((note) => (
          <article key={note.id} className="rounded-card border border-line bg-white p-4">
            <div className="flex items-center justify-between gap-3">
              <h2 className="text-sm font-medium">{note.title}</h2>
              <span className="text-xs text-ink-muted">{note.read_at ? "Read" : "Unread"}</span>
            </div>
            <p className="mt-2 text-sm leading-6 text-ink-muted">{note.message}</p>
            <p className="mt-2 text-xs text-ink-muted">{formatTimestamp(note.created_at)}</p>
          </article>
        ))}
      </div>
    </div>
  );
}
