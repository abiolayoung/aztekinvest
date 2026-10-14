import { toCents } from "@/lib/finance/money";

export type AccountSummary = {
  cashCents: bigint;
  reservedCents: bigint;
  investedCostCents: bigint;
  holdingsValueCents: bigint;
  activeHoldings: number;
  unvaluedHoldings: number;
  totalAccountValueCents: bigint;
  valuationComplete: boolean;
  confirmedDepositsCents: bigint;
  pendingDepositsCents: bigint;
  completedWithdrawalsCents: bigint;
  feesCents: bigint;
  realizedPnlCents: bigint;
  hasVerifiedValuation: boolean;
};

type SummaryRow = {
  cash_cents: string | number;
  reserved_cents: string | number;
  invested_cost_cents: string | number;
  holdings_value_cents: string | number;
  active_holdings: number;
  unvalued_holdings: number;
  total_account_value_cents: string | number;
  valuation_complete: boolean;
  confirmed_deposits_cents: string | number;
  pending_deposits_cents: string | number;
  completed_withdrawals_cents: string | number;
  fees_cents: string | number;
  realized_pnl_cents: string | number;
  has_verified_valuation: boolean;
};

export function mapSummary(row: SummaryRow): AccountSummary {
  return {
    cashCents: toCents(row.cash_cents),
    reservedCents: toCents(row.reserved_cents),
    investedCostCents: toCents(row.invested_cost_cents),
    holdingsValueCents: toCents(row.holdings_value_cents),
    activeHoldings: row.active_holdings,
    unvaluedHoldings: row.unvalued_holdings,
    totalAccountValueCents: toCents(row.total_account_value_cents),
    valuationComplete: row.valuation_complete,
    confirmedDepositsCents: toCents(row.confirmed_deposits_cents),
    pendingDepositsCents: toCents(row.pending_deposits_cents),
    completedWithdrawalsCents: toCents(row.completed_withdrawals_cents),
    feesCents: toCents(row.fees_cents),
    realizedPnlCents: toCents(row.realized_pnl_cents),
    hasVerifiedValuation: row.has_verified_valuation,
  };
}
