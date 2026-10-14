"use client";

import { useCallback, useState } from "react";
import { useRouter } from "next/navigation";
import { PlanModal } from "@/components/plans/plan-modal";

export function PlanTrigger({
  children,
  className,
  planId,
}: {
  children: React.ReactNode;
  className?: string;
  planId?: string;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const close = useCallback(() => setOpen(false), []);
  return (
    <>
      <button type="button" className={className} onClick={() => setOpen(true)}>
        {children}
      </button>
      <PlanModal
        open={open}
        onClose={close}
        initialPlanId={planId}
        chooseLabel="Sign up with"
        onChoose={(plan) => {
          setOpen(false);
          router.push(`/register?plan=${encodeURIComponent(plan.id)}`);
        }}
      />
    </>
  );
}
