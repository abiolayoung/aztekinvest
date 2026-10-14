"use client";

import { useEffect, useId, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { cn } from "@/lib/utils";
import {
  clampToPlan,
  depositRangeLabel,
  findPlan,
  formatPlanUsd,
  investmentPlans,
  projectPlan,
  sliderMaxCents,
  totalPercent,
  type InvestmentPlan,
} from "@/lib/plans";

const defaultPlan = investmentPlans.find((item) => item.tier === "featured") ?? investmentPlans[0];

function startingAmount(plan: InvestmentPlan): number {
  return plan.presetAmountsCents[2] ?? plan.minDepositCents;
}

export function PlanModal({
  open,
  onClose,
  initialPlanId,
  onChoose,
  chooseLabel = "Continue with",
}: {
  open: boolean;
  onClose: () => void;
  initialPlanId?: string | null;
  onChoose: (plan: InvestmentPlan) => void;
  chooseLabel?: string;
}) {
  const titleId = useId();
  const closeRef = useRef<HTMLButtonElement>(null);
  const [mounted, setMounted] = useState(false);
  const [visible, setVisible] = useState(false);
  const [planId, setPlanId] = useState(findPlan(initialPlanId)?.id ?? defaultPlan.id);
  const plan = findPlan(planId) ?? defaultPlan;
  const [amountCents, setAmountCents] = useState(startingAmount(plan));

  useEffect(() => setMounted(true), []);

  useEffect(() => {
    if (!open || !mounted) {
      setVisible(false);
      return;
    }
    const frame = requestAnimationFrame(() => setVisible(true));
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeRef.current?.focus();
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => {
      cancelAnimationFrame(frame);
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", onKey);
    };
  }, [open, mounted, onClose]);

  useEffect(() => {
    const next = findPlan(initialPlanId);
    if (open && next) {
      setPlanId(next.id);
      setAmountCents(startingAmount(next));
    }
  }, [open, initialPlanId]);

  if (!open || !mounted) return null;

  const belowMinimum = amountCents < plan.minDepositCents;
  const aboveMaximum = plan.maxDepositCents !== null && amountCents > plan.maxDepositCents;
  const projection = projectPlan(plan, amountCents);
  const sliderMax = sliderMaxCents(plan);

  return createPortal(
    <div className="fixed inset-0 z-[100] flex items-end justify-center sm:items-center sm:p-6">
      <button
        type="button"
        aria-label="Close plans"
        tabIndex={-1}
        onClick={onClose}
        className={cn(
          "absolute inset-0 bg-[#0B1F1A]/70 backdrop-blur-sm transition-opacity duration-300",
          visible ? "opacity-100" : "opacity-0",
        )}
      />
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        className={cn(
          "relative flex max-h-[92vh] w-full max-w-5xl flex-col overflow-hidden rounded-t-2xl bg-white shadow-2xl transition duration-300 ease-out sm:rounded-2xl",
          visible ? "translate-y-0 scale-100 opacity-100" : "translate-y-6 scale-[0.98] opacity-0",
        )}
      >
        <header className="relative overflow-hidden bg-gradient-to-br from-[#0E2F27] via-brand to-[#1F5A4A] px-6 py-6 text-white sm:px-8">
          <div className="pointer-events-none absolute -right-16 -top-20 h-56 w-56 rounded-full bg-brand-gold/20 blur-3xl" />
          <div className="pointer-events-none absolute -bottom-24 left-10 h-48 w-48 rounded-full bg-white/10 blur-3xl" />
          <div className="relative flex items-start justify-between gap-4">
            <div>
              <p className="text-xs font-medium uppercase tracking-[0.18em] text-brand-gold">Investment plans</p>
              <h2 id={titleId} className="mt-2 text-2xl font-medium sm:text-3xl">
                Choose your plan
              </h2>
              <p className="mt-1 max-w-lg text-sm text-white/75">
                Pick a plan and see what your deposit earns over the full cycle.
              </p>
            </div>
            <button
              ref={closeRef}
              type="button"
              onClick={onClose}
              aria-label="Close"
              className="rounded-full border border-white/20 p-2 text-white/80 transition hover:bg-white/10 hover:text-white"
            >
              <svg viewBox="0 0 20 20" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M5 5l10 10M15 5L5 15" strokeLinecap="round" />
              </svg>
            </button>
          </div>
        </header>

        <div className="grid flex-1 gap-0 overflow-y-auto lg:grid-cols-[1fr_1.15fr]">
          <div className="space-y-4 border-b border-line bg-canvas p-6 sm:p-8 lg:border-b-0 lg:border-r">
            <p className="text-xs font-medium uppercase tracking-wide text-ink-muted">Available plans</p>
            <div role="radiogroup" aria-label="Investment plans" className="space-y-3">
              {investmentPlans.map((item) => (
                <PlanOption
                  key={item.id}
                  plan={item}
                  selected={item.id === plan.id}
                  onSelect={() => {
                    setPlanId(item.id);
                    setAmountCents(clampToPlan(item, amountCents));
                  }}
                />
              ))}
            </div>
          </div>

          <div className="p-6 sm:p-8">
            <p className="text-xs font-medium uppercase tracking-wide text-ink-muted">Return calculator</p>
            <label htmlFor="plan-amount" className="mt-3 block text-sm font-medium">
              Deposit amount
            </label>
            <div className="mt-2 flex items-center rounded-xl border border-line bg-white px-4 focus-within:border-brand">
              <span className="text-lg text-ink-muted">$</span>
              <input
                id="plan-amount"
                inputMode="decimal"
                value={amountCents ? (amountCents / 100).toString() : ""}
                onChange={(event) => {
                  const value = Number(event.target.value.replace(/[^0-9.]/g, ""));
                  setAmountCents(Number.isFinite(value) ? Math.round(value * 100) : 0);
                }}
                className="numeric h-14 w-full bg-transparent px-2 text-2xl font-medium outline-none"
              />
              <span className="text-xs text-ink-muted">USD</span>
            </div>
            <input
              type="range"
              aria-label="Deposit amount slider"
              min={plan.minDepositCents}
              max={sliderMax}
              step={100}
              value={Math.min(Math.max(amountCents, plan.minDepositCents), sliderMax)}
              onChange={(event) => setAmountCents(Number(event.target.value))}
              className="mt-4 w-full accent-[#123C32]"
            />
            <div className="mt-1 flex justify-between text-[11px] text-ink-muted">
              <span>{formatPlanUsd(plan.minDepositCents, true)}</span>
              <span>{plan.maxDepositCents ? formatPlanUsd(plan.maxDepositCents, true) : `${formatPlanUsd(sliderMax, true)}+`}</span>
            </div>
            <div className="mt-3 flex flex-wrap gap-2">
              {plan.presetAmountsCents.map((cents) => (
                <button
                  key={cents}
                  type="button"
                  onClick={() => setAmountCents(cents)}
                  className={cn(
                    "rounded-full border px-3 py-1 text-xs transition",
                    amountCents === cents
                      ? "border-brand bg-brand text-white"
                      : "border-line bg-white text-ink hover:border-brand",
                  )}
                >
                  {formatPlanUsd(cents, true)}
                </button>
              ))}
            </div>
            {belowMinimum ? (
              <p className="mt-3 text-xs text-warning">
                The minimum deposit for {plan.name} is {formatPlanUsd(plan.minDepositCents, true)}.
              </p>
            ) : null}
            {aboveMaximum && plan.maxDepositCents ? (
              <p className="mt-3 text-xs text-warning">
                The maximum deposit for {plan.name} is {formatPlanUsd(plan.maxDepositCents, true)}. Choose a higher plan for larger amounts.
              </p>
            ) : null}

            <div className="mt-6 grid grid-cols-3 gap-3">
              <Stat label="Daily earnings" cents={projection.dailyCents} />
              <Stat label={`Profit in ${plan.durationDays} days`} cents={projection.profitCents} />
              <Stat label="Total payout" cents={projection.payoutCents} highlight />
            </div>

            <Timeline plan={plan} amountCents={amountCents} />

            <button
              type="button"
              onClick={() => onChoose(plan)}
              className="group mt-6 flex w-full items-center justify-center gap-2 rounded-xl bg-brand px-5 py-4 text-sm font-medium text-white shadow-lg shadow-brand/20 transition hover:bg-brand-hover"
            >
              {chooseLabel} {plan.name}
              <svg viewBox="0 0 20 20" className="h-4 w-4 transition group-hover:translate-x-0.5" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M4 10h12M11 5l5 5-5 5" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </button>
            <p className="mt-3 text-center text-xs leading-5 text-ink-muted">
              Figures are calculated from the plan terms. Cryptocurrency investments carry risk; review the terms before you fund your account.
            </p>
          </div>
        </div>
      </div>
    </div>,
    document.body,
  );
}

function PlanOption({ plan, selected, onSelect }: { plan: InvestmentPlan; selected: boolean; onSelect: () => void }) {
  return (
    <button
      type="button"
      role="radio"
      aria-checked={selected}
      onClick={onSelect}
      className={cn(
        "relative w-full overflow-hidden rounded-2xl border bg-white p-4 text-left transition duration-200",
        selected
          ? plan.tier === "exclusive"
            ? "border-brand-gold shadow-[0_0_0_3px_rgba(201,162,74,0.25)]"
            : "border-brand shadow-[0_0_0_3px_rgba(18,60,50,0.12)]"
          : "border-line hover:-translate-y-0.5 hover:border-brand/40 hover:shadow-md",
      )}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="flex flex-wrap items-center gap-2 text-sm font-medium text-ink">
            {plan.name}
            {plan.badge ? <PlanBadge plan={plan} /> : null}
          </p>
          <p className="mt-0.5 text-xs text-ink-muted">{plan.tagline}</p>
        </div>
        <span
          className={cn(
            "flex h-5 w-5 shrink-0 items-center justify-center rounded-full border transition",
            selected ? "border-brand bg-brand" : "border-line",
          )}
        >
          {selected ? <span className="h-2 w-2 rounded-full bg-white" /> : null}
        </span>
      </div>
      <div className="mt-3 flex items-end justify-between gap-3">
        <div className="flex items-end gap-1.5">
          <span className="numeric text-4xl font-semibold tracking-tight text-brand">{totalPercent(plan)}%</span>
          <span className="pb-1 text-xs text-ink-muted">in {plan.durationDays} days</span>
        </div>
        <div className="pb-1 text-right text-[11px] leading-4 text-ink-muted">
          <p className="font-medium text-ink">{plan.dailyPercent}% daily</p>
          <p>{depositRangeLabel(plan)}</p>
        </div>
      </div>
      <div
        className={cn(
          "grid transition-all duration-300 ease-out",
          selected ? "mt-4 grid-rows-[1fr] opacity-100" : "grid-rows-[0fr] opacity-0",
        )}
      >
        <ul className="grid gap-2 overflow-hidden sm:grid-cols-2">
          {plan.features.map((feature) => (
            <li key={feature} className="flex items-center gap-2 text-xs text-ink">
              <CheckIcon />
              {feature}
            </li>
          ))}
        </ul>
      </div>
    </button>
  );
}

function Stat({ label, cents, highlight = false }: { label: string; cents: number; highlight?: boolean }) {
  const shown = useCountUp(cents);
  return (
    <div
      className={cn(
        "rounded-xl border p-3",
        highlight ? "border-transparent bg-gradient-to-br from-brand to-[#1F5A4A] text-white" : "border-line bg-canvas",
      )}
    >
      <p className={cn("text-[11px] leading-4", highlight ? "text-white/70" : "text-ink-muted")}>{label}</p>
      <p className="numeric mt-1 truncate text-base font-semibold sm:text-lg">{formatPlanUsd(shown)}</p>
    </div>
  );
}

function Timeline({ plan, amountCents }: { plan: InvestmentPlan; amountCents: number }) {
  const { dailyCents, payoutCents } = projectPlan(plan, amountCents);
  const days = Array.from({ length: plan.durationDays }, (_, index) => index + 1);
  return (
    <div className="mt-6 rounded-xl border border-line p-4">
      <div className="flex items-center justify-between">
        <p className="text-xs font-medium text-ink">Earnings by day</p>
        <p className="text-xs text-ink-muted">+{plan.dailyPercent}% each day</p>
      </div>
      <div className="mt-4 flex gap-2">
        {days.map((day) => {
          const accrued = dailyCents * day;
          const isLast = day === plan.durationDays;
          const height = 18 + (day / plan.durationDays) * 82;
          return (
            <div key={day} className="group flex flex-1 flex-col items-center gap-1.5" title={`Day ${day}: ${formatPlanUsd(accrued)} earned`}>
              <span className="numeric h-3 whitespace-nowrap text-[10px] text-ink-muted opacity-0 transition group-hover:opacity-100">
                {formatPlanUsd(accrued)}
              </span>
              <div className="flex h-24 w-full items-end">
                <div
                  className={cn(
                    "w-full rounded-md transition-all duration-500 ease-out",
                    isLast ? "bg-brand-gold" : "bg-brand/80 group-hover:bg-brand",
                  )}
                  style={{ height: `${height}%`, transitionDelay: `${day * 40}ms` }}
                />
              </div>
              <span className="text-[10px] text-ink-muted">Day {day}</span>
            </div>
          );
        })}
      </div>
      {plan.capitalReturned ? (
        <p className="mt-3 text-xs text-ink-muted">
          On day {plan.durationDays} your capital is returned, for a total of{" "}
          <span className="numeric font-medium text-ink">{formatPlanUsd(payoutCents)}</span>.
        </p>
      ) : null}
    </div>
  );
}

function PlanBadge({ plan }: { plan: InvestmentPlan }) {
  return (
    <span
      className={cn(
        "rounded-full px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide",
        plan.tier === "exclusive" ? "bg-[#0E2F27] text-brand-gold" : "bg-brand-gold/20 text-[#7A5C1E]",
      )}
    >
      {plan.badge}
    </span>
  );
}

function CheckIcon() {
  return (
    <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-brand/10 text-brand">
      <svg viewBox="0 0 20 20" className="h-3 w-3" fill="none" stroke="currentColor" strokeWidth="2.5">
        <path d="M5 10.5l3 3 7-7" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    </span>
  );
}

function useCountUp(target: number, duration = 450) {
  const [value, setValue] = useState(target);
  const fromRef = useRef(target);
  useEffect(() => {
    const from = fromRef.current;
    if (from === target || window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      fromRef.current = target;
      setValue(target);
      return;
    }
    const start = performance.now();
    let frame = 0;
    const tick = (now: number) => {
      const progress = Math.min(1, (now - start) / duration);
      const eased = 1 - Math.pow(1 - progress, 3);
      const next = Math.round(from + (target - from) * eased);
      setValue(next);
      fromRef.current = next;
      if (progress < 1) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [target, duration]);
  return value;
}
