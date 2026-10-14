"use client";

import { useCallback, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { PlanModal } from "@/components/plans/plan-modal";
import { updatePlanAction } from "@/lib/actions/account";

export function ChangePlanButton({
  currentPlanId,
  className,
  children,
}: {
  currentPlanId?: string | null;
  className?: string;
  children: React.ReactNode;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const close = useCallback(() => setOpen(false), []);

  return (
    <>
      <button type="button" className={className} disabled={pending} onClick={() => setOpen(true)}>
        {pending ? "Saving..." : children}
      </button>
      {error ? <p className="w-full text-xs text-brand-gold">{error}</p> : null}
      <PlanModal
        open={open}
        onClose={close}
        initialPlanId={currentPlanId}
        chooseLabel="Switch to"
        onChoose={(plan) => {
          setOpen(false);
          setError(null);
          startTransition(async () => {
            const result = await updatePlanAction(plan.id);
            if (result.error) setError(result.error);
            router.refresh();
          });
        }}
      />
    </>
  );
}
