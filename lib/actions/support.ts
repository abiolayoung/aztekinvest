"use server";

import { revalidatePath } from "next/cache";
import { headers } from "next/headers";
import { requireUser } from "@/lib/auth/session";
import { publicDbError } from "@/lib/security/errors";
import { requestIp, takeRateLimit } from "@/lib/security/rate-limit";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { createClient } from "@/lib/supabase/server";
import { contactSchema, supportSchema } from "@/lib/validation/schemas";

export type ActionState = { error?: string; message?: string };

export async function contactAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  if (!isSupabaseConfigured()) {
    return { error: "The contact form is not connected yet. Use the published support email once it is configured." };
  }
  const headerStore = await headers();
  if (!takeRateLimit(`contact:${requestIp(headerStore.get("x-forwarded-for"))}`, 5, 60 * 60 * 1000)) {
    return { error: "Too many requests. Please wait and try again." };
  }
  if (String(formData.get("companyWebsite") ?? "") !== "") return { message: "Message received." };
  const parsed = contactSchema.safeParse({
    fullName: formData.get("fullName"),
    email: formData.get("email"),
    message: formData.get("message"),
    companyWebsite: "",
  });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Check the form and try again." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("submit_contact_inquiry", {
    full_name: parsed.data.fullName,
    email: parsed.data.email,
    message: parsed.data.message,
  });
  if (error) return { error: publicDbError(error, "The message could not be sent.") };
  return { message: "Message received. If a reply is needed, the team will use the email you entered." };
}

export async function createSupportAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = supportSchema.safeParse({
    subject: formData.get("subject"),
    message: formData.get("message"),
  });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Check the form and try again." };
  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("create_support_conversation", {
    subject: parsed.data.subject,
    message: parsed.data.message,
  });
  if (error) return { error: publicDbError(error, "The message could not be sent.") };
  revalidatePath("/dashboard/support");
  return { message: "Message sent to the Aztek team." };
}

export async function replySupportAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const message = String(formData.get("message") ?? "").trim();
  const conversationId = String(formData.get("conversationId") ?? "");
  if (message.length < 1) return { error: "Enter a message." };
  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("reply_support_message", {
    conversation_id: conversationId,
    message,
  });
  if (error) return { error: publicDbError(error, "The reply could not be sent.") };
  revalidatePath("/dashboard/support");
  revalidatePath("/admin/support");
  return { message: "Reply sent." };
}

export async function markNotificationsReadAction() {
  const { supabase } = await requireUser();
  await supabase.rpc("mark_notifications_read", { notification_id: null });
  revalidatePath("/dashboard/notifications");
  revalidatePath("/dashboard");
}
