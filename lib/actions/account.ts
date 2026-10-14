"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/session";
import { publicDbError } from "@/lib/security/errors";
import { profileSchema } from "@/lib/validation/schemas";

export type ActionState = { error?: string; message?: string };

export async function updateProfileAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = profileSchema.safeParse({
    fullName: formData.get("fullName"),
    countryCode: formData.get("countryCode"),
    phone: formData.get("phone") ?? "",
    emailNotifications: formData.get("emailNotifications") === "on",
  });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Check the form and try again." };
  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("update_own_profile", {
    full_name: parsed.data.fullName,
    country_code: parsed.data.countryCode,
    phone: parsed.data.phone,
    email_notifications: parsed.data.emailNotifications,
  });
  if (error) return { error: publicDbError(error, "Your profile could not be saved.") };
  revalidatePath("/dashboard/profile");
  revalidatePath("/onboarding");
  return { message: "Profile saved." };
}

export async function acknowledgeWelcomeAction(_state: ActionState, _formData: FormData): Promise<ActionState> {
  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("acknowledge_welcome");
  if (error) return { error: publicDbError(error, "The welcome step could not be saved.") };
  revalidatePath("/onboarding");
  return { message: "Welcome step saved." };
}

export async function requestReviewAction(_state: ActionState, _formData: FormData): Promise<ActionState> {
  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("request_account_review");
  if (error) return { error: publicDbError(error, "The review request could not be submitted.") };
  revalidatePath("/onboarding");
  revalidatePath("/dashboard");
  return { message: "Your account has been submitted for review." };
}

export async function completeOnboardingAction(_state: ActionState, _formData: FormData): Promise<ActionState> {
  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("complete_onboarding");
  if (error) return { error: publicDbError(error, "Onboarding could not be completed.") };
  revalidatePath("/dashboard");
  redirect("/dashboard");
}
