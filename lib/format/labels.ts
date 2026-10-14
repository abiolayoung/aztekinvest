export const depositStatusLabel: Record<string, string> = {
  draft: "Draft",
  awaiting_payment: "Waiting for your payment",
  payment_detected: "Payment detected",
  confirming: "Waiting for blockchain confirmations",
  under_review: "Receipt uploaded — pending admin Received",
  credited: "Received and credited to balance",
  rejected: "Deposit could not be approved",
  expired: "Payment request expired",
  cancelled: "Cancelled",
};

export const withdrawalStatusLabel: Record<string, string> = {
  requested: "Submitted for review",
  under_review: "Under review",
  approved: "Approved",
  processing: "Processing",
  completed: "Completed",
  rejected: "Rejected",
  cancelled: "Cancelled",
  failed: "Failed",
};

export const verificationLabel: Record<string, string> = {
  unverified: "Not submitted",
  pending_review: "Pending review",
  verified: "Approved",
  rejected: "Not approved",
};

export const accountStatusLabel: Record<string, string> = {
  pending: "Pending",
  active: "Active",
  restricted: "Restricted",
  suspended: "Suspended",
  closed: "Closed",
};

export const categoryLabel: Record<string, string> = {
  digital_asset_trading: "Digital asset trading",
  currency_market_operations: "Currency market operations",
  diversified_strategies: "Diversified investment strategies",
  private_business: "Startup or private business investments",
  other_managed: "Other managed investments",
};

export const ledgerTypeLabel: Record<string, string> = {
  deposit_credit: "Deposit credited",
  signup_bonus: "Welcome bonus",
  withdrawal_reserve: "Withdrawal reserved",
  withdrawal_release: "Withdrawal reservation released",
  withdrawal_complete: "Withdrawal completed",
  investment_allocation: "Allocated to managed investment",
  investment_close: "Investment proceeds recorded",
  fee: "Fee",
  adjustment: "Account adjustment",
};

export function labelFor(map: Record<string, string>, value: string): string {
  return map[value] ?? value.replaceAll("_", " ");
}
