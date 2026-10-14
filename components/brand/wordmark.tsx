import Link from "next/link";
import { cn } from "@/lib/utils";

export function Wordmark({ href = "/", compact = false, className }: { href?: string; compact?: boolean; className?: string }) {
  return (
    <Link href={href} className={cn("inline-flex flex-col leading-none", className)}>
      <span className="text-[15px] font-semibold tracking-[0.16em] text-brand">AZTEK</span>
      {compact ? null : <span className="mt-1 text-[10px] tracking-[0.18em] text-ink-muted">INVESTMENT</span>}
      <span className="mt-1.5 h-px w-8 bg-brand-gold" aria-hidden="true" />
    </Link>
  );
}
