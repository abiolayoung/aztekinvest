import type { ReactNode } from "react";
import { formatUsdCents } from "@/lib/finance/money";

export function PageIntro({ title, body }: { title: string; body?: string }) {
  return (
    <div className="mb-6">
      <h1 className="text-2xl font-medium tracking-tight text-ink">{title}</h1>
      {body ? <p className="mt-1 max-w-2xl text-sm leading-6 text-ink-muted">{body}</p> : null}
    </div>
  );
}

export function EmptyState({ title, body, action }: { title: string; body: string; action?: ReactNode }) {
  return (
    <div className="rounded-card border border-dashed border-line bg-white px-5 py-8">
      <p className="font-medium text-ink">{title}</p>
      <p className="mt-1 text-sm leading-6 text-ink-muted">{body}</p>
      {action ? <div className="mt-4">{action}</div> : null}
    </div>
  );
}

export function Money({ cents }: { cents: bigint | string | number | null | undefined }) {
  return <span className="numeric">{formatUsdCents(cents)}</span>;
}
