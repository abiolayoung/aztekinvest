export const roles = ["client", "support", "compliance", "portfolio_manager", "admin"] as const;
export type UserRole = (typeof roles)[number];

const staff = new Set<UserRole>(["support", "compliance", "portfolio_manager", "admin"]);

export function isStaffRole(role: string): boolean {
  return staff.has(role as UserRole);
}

export function can(role: string, capability: Capability): boolean {
  return capabilityRoles[capability].includes(role as UserRole);
}

export type Capability =
  | "reviewDeposits"
  | "manageWallets"
  | "manageSettings"
  | "reviewWithdrawals"
  | "manageClients"
  | "reviewVerification"
  | "viewClients"
  | "manageInvestments"
  | "viewLedger"
  | "supportReply"
  | "viewAudit"
  | "sendNotices"
  | "postAdjustments";

const capabilityRoles: Record<Capability, UserRole[]> = {
  reviewDeposits: ["admin"],
  manageWallets: ["admin"],
  manageSettings: ["admin"],
  reviewWithdrawals: ["admin"],
  manageClients: ["admin"],
  postAdjustments: ["admin"],
  reviewVerification: ["admin", "compliance"],
  viewClients: ["admin", "support", "compliance", "portfolio_manager"],
  manageInvestments: ["admin", "portfolio_manager"],
  viewLedger: ["admin", "support", "compliance", "portfolio_manager"],
  supportReply: ["admin", "support"],
  viewAudit: ["admin", "compliance"],
  sendNotices: ["admin", "support"],
};
