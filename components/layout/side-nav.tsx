"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";

export type NavItem = { href: string; label: string };

export function SideNav({ items, label }: { items: NavItem[]; label: string }) {
  const path = usePathname();
  return (
    <nav className="flex flex-col gap-1" aria-label={label}>
      {items.map((item) => {
        const active =
          item.href === "/dashboard" || item.href === "/admin"
            ? path === item.href
            : path === item.href || path.startsWith(`${item.href}/`);
        return (
          <Link
            key={item.href}
            href={item.href}
            aria-current={active ? "page" : undefined}
            className={cn(
              "rounded-lg px-3 py-2 text-sm transition duration-ui",
              active ? "bg-brand text-white" : "text-ink-muted hover:bg-muted hover:text-ink",
            )}
          >
            {item.label}
          </Link>
        );
      })}
    </nav>
  );
}
