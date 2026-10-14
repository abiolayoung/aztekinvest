import { cn } from "@/lib/utils";

const tones: Record<string, string> = {
  neutral: "bg-muted text-ink",
  positive: "bg-emerald-50 text-success",
  warning: "bg-amber-50 text-warning",
  danger: "bg-red-50 text-danger",
  info: "bg-sky-50 text-info",
};

const statusTone: Record<string, string> = {
  credited: "positive",
  completed: "positive",
  verified: "positive",
  active: "positive",
  approved: "info",
  processing: "info",
  confirming: "info",
  payment_detected: "info",
  under_review: "warning",
  pending_review: "warning",
  requested: "warning",
  awaiting_payment: "warning",
  pending: "warning",
  rejected: "danger",
  failed: "danger",
  suspended: "danger",
  expired: "neutral",
  cancelled: "neutral",
  closed: "neutral",
};

export function StatusBadge({ status, label }: { status: string; label: string }) {
  const tone = tones[statusTone[status] ?? "neutral"];
  return (
    <span className={cn("inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium", tone)}>
      {label}
    </span>
  );
}
