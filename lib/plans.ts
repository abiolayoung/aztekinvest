export type InvestmentPlan = {
  id: string;
  name: string;
  tagline: string;
  badge: string | null;
  tier: "standard" | "featured" | "exclusive";
  dailyPercent: number;
  durationDays: number;
  minDepositCents: number;
  maxDepositCents: number | null;
  capitalReturned: boolean;
  referralCommissionPercent: number;
  presetAmountsCents: number[];
  features: string[];
};

export const investmentPlans: InvestmentPlan[] = [
  {
    id: "starter-6d",
    name: "Starter",
    tagline: "A short 6-day cycle to get started.",
    badge: null,
    tier: "standard",
    dailyPercent: 2,
    durationDays: 6,
    minDepositCents: 10_000,
    maxDepositCents: 999_900,
    capitalReturned: true,
    referralCommissionPercent: 10,
    presetAmountsCents: [10_000, 50_000, 100_000, 500_000],
    features: [
      "2% daily for 6 days",
      "Minimum deposit $100",
      "Maximum deposit $9,999",
      "Capital is returned",
      "10% referral commission",
      "24/7 live support",
    ],
  },
  {
    id: "mid-6d",
    name: "Mid Level",
    tagline: "Higher daily returns over the same 6 days.",
    badge: "Most popular",
    tier: "featured",
    dailyPercent: 3.2,
    durationDays: 6,
    minDepositCents: 10_000,
    maxDepositCents: null,
    capitalReturned: true,
    referralCommissionPercent: 10,
    presetAmountsCents: [10_000, 100_000, 500_000, 2_000_000],
    features: [
      "3.2% daily for 6 days",
      "Minimum deposit $100",
      "Capital is returned",
      "10% referral commission",
      "24/7 live support",
    ],
  },
  {
    id: "exclusive-6d",
    name: "Exclusive",
    tagline: "Our top tier for larger portfolios.",
    badge: "Exclusive",
    tier: "exclusive",
    dailyPercent: 4.5,
    durationDays: 6,
    minDepositCents: 4_000_000,
    maxDepositCents: null,
    capitalReturned: true,
    referralCommissionPercent: 10,
    presetAmountsCents: [4_000_000, 5_000_000, 10_000_000, 25_000_000],
    features: [
      "4.5% daily for 6 days",
      "Minimum deposit $40,000",
      "Unlimited maximum deposit",
      "Capital is returned",
      "10% referral commission",
      "24/7 live support",
    ],
  },
];

export const planIds = investmentPlans.map((plan) => plan.id) as [string, ...string[]];

export function findPlan(id: string | null | undefined): InvestmentPlan | null {
  if (!id) return null;
  return investmentPlans.find((plan) => plan.id === id) ?? null;
}

export function totalPercent(plan: InvestmentPlan): number {
  return Math.round(plan.dailyPercent * plan.durationDays * 100) / 100;
}

export function projectPlan(plan: InvestmentPlan, amountCents: number) {
  const dailyCents = Math.round((amountCents * plan.dailyPercent) / 100);
  const profitCents = dailyCents * plan.durationDays;
  const payoutCents = profitCents + (plan.capitalReturned ? amountCents : 0);
  return { dailyCents, profitCents, payoutCents };
}

export function sliderMaxCents(plan: InvestmentPlan): number {
  return plan.maxDepositCents ?? Math.max(plan.minDepositCents * 10, 5_000_000);
}

export function clampToPlan(plan: InvestmentPlan, amountCents: number): number {
  const max = plan.maxDepositCents ?? Number.MAX_SAFE_INTEGER;
  return Math.min(Math.max(amountCents, plan.minDepositCents), max);
}

export function depositRangeLabel(plan: InvestmentPlan): string {
  const min = formatPlanUsd(plan.minDepositCents, true);
  return plan.maxDepositCents ? `${min} – ${formatPlanUsd(plan.maxDepositCents, true)}` : `${min} – unlimited`;
}

export function formatPlanUsd(cents: number, whole = false): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: whole ? 0 : 2,
    minimumFractionDigits: whole ? 0 : 2,
  }).format(cents / 100);
}
