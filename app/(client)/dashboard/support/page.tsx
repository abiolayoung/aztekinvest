import { createSupportAction, replySupportAction } from "@/lib/actions/support";
import { StateForm } from "@/components/forms/state-form";
import { Input, Label, Textarea } from "@/components/ui/fields";
import { PageIntro } from "@/components/ui/page";
import { requireUser } from "@/lib/auth/session";
import { formatTimestamp } from "@/lib/format/date";

export default async function SupportPage() {
  const { supabase, user } = await requireUser();
  const { data: conversations } = await supabase.from("support_conversations").select("id, subject, status, created_at").eq("user_id", user.id).order("created_at", { ascending: false });
  const ids = (conversations ?? []).map((item) => item.id);
  const { data: messages } = ids.length
    ? await supabase.from("support_messages").select("id, conversation_id, message, created_at, sender_user_id").in("conversation_id", ids).order("created_at", { ascending: true })
    : { data: [] };

  return (
    <div className="grid gap-6 lg:grid-cols-[360px_1fr]">
      <div>
        <PageIntro title="Help and support" body="Messages are visible to you and authorized Aztek staff." />
        <StateForm action={createSupportAction} submitLabel="Send message">
          <div>
            <Label htmlFor="subject">Subject</Label>
            <Input id="subject" name="subject" required />
          </div>
          <div>
            <Label htmlFor="message">Message</Label>
            <Textarea id="message" name="message" required />
          </div>
        </StateForm>
      </div>
      <div className="space-y-4">
        {(conversations ?? []).length === 0 ? <p className="text-sm text-ink-muted">No conversations yet.</p> : null}
        {(conversations ?? []).map((conversation) => (
          <article key={conversation.id} className="rounded-card border border-line bg-white p-4">
            <h2 className="font-medium">{conversation.subject}</h2>
            <p className="text-xs text-ink-muted">{conversation.status} · {formatTimestamp(conversation.created_at)}</p>
            <div className="mt-3 space-y-2">
              {(messages ?? []).filter((message) => message.conversation_id === conversation.id).map((message) => (
                <p key={message.id} className="rounded-lg bg-muted px-3 py-2 text-sm">
                  {message.message}
                  <span className="mt-1 block text-xs text-ink-muted">{message.sender_user_id === user.id ? "You" : "Aztek"} · {formatTimestamp(message.created_at)}</span>
                </p>
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
