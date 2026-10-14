import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";
import { AppShell } from "@/components/layout/app-shell";
import { isStaffRole } from "@/lib/auth/permissions";
import { requireUser } from "@/lib/auth/session";
import { signOutAction } from "@/lib/actions/auth";

const items = [
  { href: "/dashboard", label: "Overview" },
  { href: "/dashboard/deposit", label: "Deposit" },
  { href: "/dashboard/portfolio", label: "Portfolio" },
  { href: "/dashboard/withdrawals", label: "Withdrawals" },
  { href: "/dashboard/deposits", label: "Deposit history" },
  { href: "/dashboard/activity", label: "Activity" },
  { href: "/dashboard/transactions", label: "Transactions" },
  { href: "/dashboard/notifications", label: "Notifications" },
  { href: "/dashboard/support", label: "Support" },
  { href: "/dashboard/profile", label: "Profile" },
];

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const { profile, user, supabase } = await requireUser();
  if (isStaffRole(profile.role)) redirect("/admin");
  if (profile.account_status === "suspended" || profile.account_status === "closed") {
    return (
      <main className="mx-auto max-w-lg px-5 py-20">
        <h1 className="text-2xl font-medium">Account unavailable</h1>
        <p className="mt-2 text-sm text-ink-muted">This account is {profile.account_status}. Funding and requests are disabled.</p>
        <form action={signOutAction} className="mt-6">
          <button className="rounded-lg bg-brand px-4 py-2 text-sm text-white" type="submit">Sign out</button>
        </form>
      </main>
    );
  }
  if (!profile.onboarding_completed_at) redirect("/onboarding");
  const { count } = await supabase
    .from("notifications")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id)
    .is("read_at", null);

  return (
    <AppShell items={items} title="Managed account" homeHref="/dashboard" profileName={profile.full_name} unread={count ?? 0}>
      {children}
    </AppShell>
  );
}
