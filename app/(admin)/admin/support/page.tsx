import { replySupportAction } from "@/lib/actions/support";
import { StateForm } from "@/components/forms/state-form";
import { Label, Textarea } from "@/components/ui/fields";
import { PageIntro } from "@/components/ui/page";
import { can } from "@/lib/auth/permissions";
import { requireUser } from "@/lib/auth/session";
import { formatTimestamp } from "@/lib/format/date";

export default async function AdminSupportPage() {
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "supportReply")) return <p>You do not have permission to answer support messages.</p>;
  const { data: conversations } = await supabase.from("support_conversations").select("id, user_id, subject, status, created_at").order("created_at", { ascending: false }).limit(50);
  const ids = (conversations ?? []).map((item) => item.id);
  const { data: messages } = ids.length ? await supabase.from("support_messages").select("id, conversation_id, message, created_at, sender_user_id").in("conversation_id", ids) : { data: [] };
  return (
    <div>
      <PageIntro title="Support" />
      <div className="space-y-4">
        {(conversations ?? []).map((conversation) => (
          <article key={conversation.id} className="rounded-card border border-line bg-white p-4">
            <h2 className="font-medium">{conversation.subject}</h2>
            <p className="text-xs text-ink-muted">{conversation.status} · {formatTimestamp(conversation.created_at)}</p>
            <div className="mt-3 space-y-2">
              {(messages ?? []).filter((message) => message.conversation_id === conversation.id).map((message) => (
                <p key={message.id} className="rounded-lg bg-muted px-3 py-2 text-sm">{message.message}</p>
              ))}
            </div>
            <div className="mt-3">
              <StateForm action={replySupportAction} submitLabel="Reply">
                <input type="hidden" name="conversationId" value={conversation.id} />
                <Label htmlFor={`reply-${conversation.id}`}>Reply</Label>
                <Textarea id={`reply-${conversation.id}`} name="message" required />
              </StateForm>
            </div>
          </article>
        ))}
      </div>
    </div>
  );
}
