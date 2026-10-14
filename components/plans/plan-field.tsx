"use client";

import { useCallback, useState } from "react";
import { PlanModal } from "@/components/plans/plan-modal";
import { depositRangeLabel, findPlan, totalPercent } from "@/lib/plans";

export function PlanField({ initialPlanId }: { initialPlanId?: string | null }) {
  const [planId, setPlanId] = useState(findPlan(initialPlanId)?.id ?? "");
  const [open, setOpen] = useState(!findPlan(initialPlanId));
  const close = useCallback(() => setOpen(false), []);
  const plan = findPlan(planId);

  return (
    <div>
      <input type="hidden" name="planId" value={planId} />
      <p className="mb-1.5 text-sm font-medium text-ink">Investment plan</p>
      {plan ? (
        <div className="flex items-center justify-between gap-3 rounded-xl border border-brand/30 bg-gradient-to-br from-brand/5 to-transparent p-4">
          <div>
            <p className="text-sm font-medium">
              {plan.name} <span className="text-brand">· {totalPercent(plan)}% in {plan.durationDays} days</span>
            </p>
            <p className="mt-0.5 text-xs text-ink-muted">
              {plan.dailyPercent}% daily · {depositRangeLabel(plan)}
              {plan.capitalReturned ? " · capital returned" : ""}
            </p>
          </div>
          <button type="button" onClick={() => setOpen(true)} className="shrink-0 text-sm text-brand hover:underline">
            Change
          </button>
        </div>
      ) : (
        <button
          type="button"
          onClick={() => setOpen(true)}
          className="flex w-full items-center justify-center rounded-xl border border-dashed border-brand/40 p-4 text-sm text-brand hover:bg-brand/5"
        >
          Choose an investment plan to continue
        </button>
      )}
      <PlanModal
        open={open}
        onClose={close}
        initialPlanId={planId}
        chooseLabel="Select"
        onChoose={(chosen) => {
          setPlanId(chosen.id);
          setOpen(false);
        }}
      />
    </div>
  );
}
