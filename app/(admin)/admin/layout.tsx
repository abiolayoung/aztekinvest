import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";
import { AppShell } from "@/components/layout/app-shell";
import { can, isStaffRole, type Capability } from "@/lib/auth/permissions";
import { requireUser } from "@/lib/auth/session";

const items: { href: string; label: string; capability?: Capability }[] = [
  { href: "/admin", label: "Overview" },
  { href: "/admin/deposits", label: "Deposits", capability: "reviewDeposits" },
  { href: "/admin/withdrawals", label: "Withdrawals", capability: "reviewWithdrawals" },
  { href: "/admin/clients", label: "Clients", capability: "viewClients" },
  { href: "/admin/portfolios", label: "Portfolios", capability: "manageInvestments" },
  { href: "/admin/investments", label: "Investments", capability: "viewLedger" },
  { href: "/admin/wallets", label: "Wallets", capability: "manageWallets" },
  { href: "/admin/support", label: "Support", capability: "supportReply" },
  { href: "/admin/notifications", label: "Notices", capability: "sendNotices" },
  { href: "/admin/audit-logs", label: "Audit logs", capability: "viewAudit" },
  { href: "/admin/settings", label: "Settings", capability: "manageSettings" },
];

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const { profile } = await requireUser();
  if (!isStaffRole(profile.role)) redirect("/dashboard");
  const visible = items.filter((item) => !item.capability || can(profile.role, item.capability));
  return (
    <AppShell items={visible} title="Operations" homeHref="/admin" profileName={profile.full_name}>
      {children}
    </AppShell>
  );
}
