"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { homeForRole } from "@/lib/auth/session";
import { publicDbError } from "@/lib/security/errors";
import { requestIp, takeRateLimit } from "@/lib/security/rate-limit";
import { appUrl, isSupabaseConfigured } from "@/lib/supabase/config";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import { processNotificationOutbox } from "@/lib/notifications/dispatch";
import {
  forgotPasswordSchema,
  loginSchema,
  registerSchema,
  resetPasswordSchema,
} from "@/lib/validation/schemas";

import type { ActionState } from "@/lib/actions/types";
export type { ActionState };

async function guard(bucket: string, limit: number): Promise<ActionState | null> {
  if (!isSupabaseConfigured()) {
    return { error: "Account services are not configured yet. Add the Supabase environment variables to continue." };
  }
  const headerStore = await headers();
  const ip = requestIp(headerStore.get("x-forwarded-for"));
  if (!takeRateLimit(`${bucket}:${ip}`, limit, 15 * 60 * 1000)) {
    return { error: "Too many requests. Please wait and try again." };
  }
  return null;
}

function authSignupError(error: { message?: string; code?: string; status?: number } | null): string {
  const message = (error?.message ?? "").toLowerCase();
  const code = (error?.code ?? "").toLowerCase();
  if (code.includes("rate_limit") || message.includes("rate limit") || message.includes("email rate limit")) {
    return "Too many signup emails were sent recently. Wait a few minutes, or ask an administrator to confirm your account.";
  }
  if (message.includes("already registered") || message.includes("already been registered") || code.includes("user_already_exists")) {
    return "An account with this email already exists. Sign in instead.";
  }
  if (message.includes("database error creating new user")) {
    return "Account setup is blocked by a database trigger. Run supabase/FIX_SIGNUP_NOW.sql in the Supabase SQL editor, then try again.";
  }
  return publicDbError(error, "The account could not be created.");
}

async function finalizeNewClient(userId: string) {
  const admin = createAdminClient();
  if (!admin) return;
  // Best-effort welcome bonus. Never fail registration if this lags.
  await admin.rpc("grant_signup_bonus", { target_user: userId });
  // Emails must not block the signup redirect (Resend latency / rate limits).
  void processNotificationOutbox().catch(() => undefined);
}

export async function registerAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const limited = await guard("register", 8);
  if (limited) return limited;
  const parsed = registerSchema.safeParse({
    fullName: formData.get("fullName"),
    email: formData.get("email"),
    password: formData.get("password"),
    confirmPassword: formData.get("confirmPassword"),
    countryCode: formData.get("countryCode"),
    acceptTerms: formData.get("acceptTerms") === "on",
  });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Check the form and try again." };

  const admin = createAdminClient();
  if (admin) {
    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email: parsed.data.email,
      password: parsed.data.password,
      email_confirm: true,
      user_metadata: {
        full_name: parsed.data.fullName,
        country_code: parsed.data.countryCode,
      },
    });
    if (createError) return { error: authSignupError(createError) };
    if (!created.user) return { error: "The account could not be created." };

    await finalizeNewClient(created.user.id);

    const supabase = await createClient();
    const { error: signInError } = await supabase.auth.signInWithPassword({
      email: parsed.data.email,
      password: parsed.data.password,
    });
    if (signInError) {
      redirect("/login?registered=1");
    }
    redirect("/onboarding");
  }

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signUp({
    email: parsed.data.email,
    password: parsed.data.password,
    options: {
      emailRedirectTo: `${appUrl()}/auth/callback?next=/onboarding`,
      data: {
        full_name: parsed.data.fullName,
        country_code: parsed.data.countryCode,
      },
    },
  });
  if (error) return { error: authSignupError(error) };
  if (data.user) await finalizeNewClient(data.user.id);
  if (!data.session) {
    redirect("/register/check-email");
  }
  redirect("/onboarding");
}

export async function loginAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const limited = await guard("login", 10);
  if (limited) return limited;
  const parsed = loginSchema.safeParse({
    email: formData.get("email"),
    password: formData.get("password"),
  });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Check the form and try again." };

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword(parsed.data);
  if (error) return { error: "The email or password was not accepted." };

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "The email or password was not accepted." };
  const { data: profile } = await supabase.from("profiles").select("role, onboarding_completed_at").eq("id", user.id).maybeSingle();
  redirect(homeForRole(profile?.role ?? "client", Boolean(profile?.onboarding_completed_at)));
}

export async function forgotPasswordAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const limited = await guard("forgot", 5);
  if (limited) return limited;
  const parsed = forgotPasswordSchema.safeParse({ email: formData.get("email") });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Enter a valid email address." };
  const supabase = await createClient();
  const { error } = await supabase.auth.resetPasswordForEmail(parsed.data.email, {
    redirectTo: `${appUrl()}/auth/callback?next=/reset-password`,
  });
  if (error) {
    if (/rate limit/i.test(error.message)) {
      return { error: "Too many password reset emails were sent. Please wait a few minutes and try again." };
    }
    return { error: publicDbError(error, "If that email exists, a reset link will be sent.") };
  }
  return { message: "If that email exists, a reset link has been sent." };
}

export async function resetPasswordAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = resetPasswordSchema.safeParse({
    password: formData.get("password"),
    confirmPassword: formData.get("confirmPassword"),
  });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Check the form and try again." };
  const supabase = await createClient();
  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error) return { error: publicDbError(error, "The password could not be updated.") };
  redirect("/login?reset=1");
}

export async function signOutAction() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}
