import "server-only";

import { sendTransactionalEmail } from "@/lib/notifications/email";
import { createAdminClient } from "@/lib/supabase/admin";

export async function processNotificationOutbox(limit = 25): Promise<{
  sent: number;
  skipped: number;
  failed: number;
}> {
  const admin = createAdminClient();
  if (!admin) return { sent: 0, skipped: 0, failed: 0 };

  const { data, error } = await admin
    .from("notification_outbox")
    .select("id, recipient_email, subject, body, attempts")
    .eq("status", "pending")
    .order("created_at", { ascending: true })
    .limit(limit);

  if (error || !data?.length) return { sent: 0, skipped: 0, failed: 0 };

  let sent = 0;
  let skipped = 0;
  let failed = 0;

  for (const row of data) {
    const result = await sendTransactionalEmail({
      to: row.recipient_email,
      subject: row.subject,
      text: row.body,
    });
    const status =
      result.status === "sent"
        ? "sent"
        : result.status === "skipped_unconfigured"
          ? "skipped_unconfigured"
          : "failed";
    await admin
      .from("notification_outbox")
      .update({
        status,
        attempts: row.attempts + 1,
        last_error: result.error ?? null,
        sent_at: status === "sent" ? new Date().toISOString() : null,
      })
      .eq("id", row.id);
    if (status === "sent") sent += 1;
    else if (status === "skipped_unconfigured") skipped += 1;
    else failed += 1;
  }

  return { sent, skipped, failed };
}
