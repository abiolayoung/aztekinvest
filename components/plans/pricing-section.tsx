import Link from "next/link";
import { PlanTrigger } from "@/components/plans/plan-trigger";
import { cn } from "@/lib/utils";
import {
  depositRangeLabel,
  formatPlanUsd,
  investmentPlans,
  projectPlan,
  totalPercent,
  type InvestmentPlan,
} from "@/lib/plans";

export function PricingSection() {
  return (
    <section id="plans" className="relative overflow-hidden bg-gradient-to-br from-[#0E2F27] via-brand to-[#1F5A4A] text-white">
      <div className="pointer-events-none absolute -right-24 top-0 h-80 w-80 rounded-full bg-brand-gold/15 blur-3xl" />
      <div className="pointer-events-none absolute -left-24 bottom-0 h-72 w-72 rounded-full bg-white/10 blur-3xl" />
      <div className="relative mx-auto max-w-content px-5 py-16 lg:py-24">
        <div className="mx-auto max-w-2xl text-center">
          <p className="text-xs font-medium uppercase tracking-[0.18em] text-brand-gold">Investment plans</p>
          <h2 className="mt-3 text-3xl font-medium tracking-tight sm:text-4xl">Choose the plan that fits you</h2>
          <p className="mt-3 text-sm leading-6 text-white/75">
            Three 6-day plans with full terms up front. Apply now to sign up, or open the calculator to see what your deposit earns each day.
          </p>
        </div>

        <div className="mx-auto mt-14 grid max-w-6xl items-stretch gap-6 lg:grid-cols-3 lg:gap-5">
          {investmentPlans.map((plan) => (
            <PlanCard key={plan.id} plan={plan} />
          ))}
        </div>

        <div className="mx-auto mt-12 flex max-w-3xl flex-wrap items-center justify-center gap-x-8 gap-y-3 text-sm text-white/80">
          {["Capital returned on every plan", "10% referral commission", "24/7 live support"].map((item) => (
            <span key={item} className="flex items-center gap-2">
              <Tick className="bg-brand-gold/20 text-brand-gold" />
              {item}
            </span>
          ))}
        </div>
      </div>
    </section>
  );
}

function PlanCard({ plan }: { plan: InvestmentPlan }) {
  const exclusive = plan.tier === "exclusive";
  const featured = plan.tier === "featured";
  const exampleCents = plan.presetAmountsCents[2] ?? plan.minDepositCents;
  const example = projectPlan(plan, exampleCents);

  return (
    <article
      className={cn(
        "group relative flex flex-col rounded-3xl p-7 shadow-xl transition duration-300 hover:-translate-y-1.5 hover:shadow-2xl",
        exclusive
          ? "bg-gradient-to-b from-[#0B1F1A] to-[#123C32] text-white ring-1 ring-brand-gold/60"
          : "bg-white text-ink",
        featured && "ring-2 ring-brand-gold lg:-translate-y-3 lg:hover:-translate-y-4",
      )}
    >
      {plan.badge ? (
        <span className="absolute -top-3 left-7 flex items-center gap-1.5 rounded-full bg-brand-gold px-3 py-1 text-[11px] font-medium uppercase tracking-wide text-[#0E2F27] shadow-md">
          {exclusive ? (
            <svg viewBox="0 0 20 20" className="h-3 w-3" fill="currentColor">
              <path d="M3 6l3.5 3L10 3l3.5 6L17 6l-1.5 9h-11L3 6z" />
            </svg>
          ) : (
            <svg viewBox="0 0 20 20" className="h-3 w-3" fill="currentColor">
              <path d="M10 2l2.4 5 5.6.8-4 3.9.9 5.5L10 14.6 5.1 17.2l.9-5.5-4-3.9 5.6-.8L10 2z" />
            </svg>
          )}
          {plan.badge}
        </span>
      ) : null}

      <div className="flex items-start justify-between gap-3">
        <div>
          <p className={cn("text-lg font-medium", exclusive && "text-brand-gold")}>{plan.name}</p>
          <p className={cn("mt-0.5 text-xs", exclusive ? "text-white/65" : "text-ink-muted")}>{plan.tagline}</p>
        </div>
        <span
          className={cn(
            "shrink-0 whitespace-nowrap rounded-full px-2.5 py-1 text-[11px] font-medium",
            exclusive ? "bg-white/10 text-white" : "bg-brand/10 text-brand",
          )}
        >
          {plan.durationDays} days
        </span>
      </div>

      <div className="mt-6 flex items-end gap-2">
        <span
          className={cn(
            "numeric text-6xl font-semibold tracking-tight",
            exclusive ? "bg-gradient-to-br from-[#F2D58A] to-brand-gold bg-clip-text text-transparent" : "text-brand",
          )}
        >
          {totalPercent(plan)}%
        </span>
        <span className={cn("pb-2 text-sm", exclusive ? "text-white/65" : "text-ink-muted")}>in {plan.durationDays} days</span>
      </div>

      <div className="mt-3 flex flex-wrap gap-2 text-[11px] font-medium">
        <span className={cn("rounded-full px-2.5 py-1", exclusive ? "bg-brand-gold/15 text-brand-gold" : "bg-brand-gold/15 text-[#7A5C1E]")}>
          {plan.dailyPercent}% daily
        </span>
        <span className={cn("rounded-full px-2.5 py-1", exclusive ? "bg-white/10 text-white/85" : "bg-canvas text-ink")}>
          {depositRangeLabel(plan)}
        </span>
      </div>

      <div
        className={cn(
          "mt-5 rounded-2xl px-4 py-3 text-xs",
          exclusive ? "bg-white/5 text-white/75" : "bg-canvas text-ink-muted",
        )}
      >
        Deposit <span className={cn("numeric font-medium", exclusive ? "text-white" : "text-ink")}>{formatPlanUsd(exampleCents, true)}</span>
        {" → "}receive{" "}
        <span className={cn("numeric font-semibold", exclusive ? "text-brand-gold" : "text-brand")}>
          {formatPlanUsd(example.payoutCents, true)}
        </span>{" "}
        after {plan.durationDays} days
      </div>

      <ul className="mt-6 flex-1 space-y-3">
        {plan.features.map((feature) => (
          <li key={feature} className="flex items-center gap-2.5 text-sm">
            <Tick className={exclusive ? "bg-brand-gold text-[#0E2F27]" : "bg-brand text-white"} />
            {feature}
          </li>
        ))}
      </ul>

      <Link
        href={`/register?plan=${encodeURIComponent(plan.id)}`}
        className={cn(
          "group/apply mt-8 flex w-full items-center justify-center gap-2 rounded-xl px-4 py-3.5 text-sm font-semibold shadow-lg transition",
          exclusive
            ? "bg-gradient-to-r from-[#F2D58A] to-brand-gold text-[#0E2F27] shadow-brand-gold/20 hover:brightness-105"
            : "bg-brand text-white shadow-brand/25 hover:bg-brand-hover",
        )}
      >
        Apply now
        <svg viewBox="0 0 20 20" className="h-4 w-4 transition group-hover/apply:translate-x-1" fill="none" stroke="currentColor" strokeWidth="2">
          <path d="M4 10h12M11 5l5 5-5 5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </Link>
      <PlanTrigger
        planId={plan.id}
        className={cn(
          "mt-2.5 w-full rounded-xl px-4 py-2.5 text-xs font-medium transition",
          exclusive ? "text-white/70 hover:bg-white/5 hover:text-white" : "text-ink-muted hover:bg-canvas hover:text-ink",
        )}
      >
        Calculate my returns
      </PlanTrigger>
    </article>
  );
}

function Tick({ className }: { className?: string }) {
  return (
    <span className={cn("flex h-5 w-5 shrink-0 items-center justify-center rounded-full", className)}>
      <svg viewBox="0 0 20 20" className="h-3 w-3" fill="none" stroke="currentColor" strokeWidth="3">
        <path d="M5 10.5l3 3 7-7" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    </span>
  );
}
