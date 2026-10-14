import "server-only";
import { redirect } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { isStaffRole, type UserRole } from "@/lib/auth/permissions";
import { createClient } from "@/lib/supabase/server";
import { isSupabaseConfigured } from "@/lib/supabase/config";

export type Profile = {
  id: string;
  full_name: string;
  country_code: string | null;
  phone: string | null;
  role: UserRole;
  account_status: "pending" | "active" | "restricted" | "suspended" | "closed";
  email_verified_at: string | null;
  verification_status: "unverified" | "pending_review" | "verified" | "rejected";
  notification_preferences: { email?: boolean; in_app?: boolean };
  onboarding_welcome_at: string | null;
  onboarding_completed_at: string | null;
  selected_plan: string | null;
  selected_plan_at: string | null;
};

export async function getSession() {
  if (!isSupabaseConfigured()) {
    return { configured: false as const, supabase: null, user: null, profile: null };
  }
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { configured: true as const, supabase, user: null, profile: null };
  const { data } = await supabase.from("profiles").select("*").eq("id", user.id).maybeSingle();
  return {
    configured: true as const,
    supabase,
    user,
    profile: (data as Profile | null) ?? null,
  };
}

export async function requireUser(): Promise<{
  supabase: NonNullable<Awaited<ReturnType<typeof getSession>>["supabase"]>;
  user: User;
  profile: Profile;
}> {
  const session = await getSession();
  if (!session.configured) redirect("/setup");
  if (!session.user || !session.profile || !session.supabase) redirect("/login");
  return { supabase: session.supabase, user: session.user, profile: session.profile };
}

export function homeForRole(role: string, onboarded: boolean): string {
  if (isStaffRole(role)) return "/admin";
  return onboarded ? "/dashboard" : "/onboarding";
}
