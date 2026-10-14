import Link from "next/link";
import { Wordmark } from "@/components/brand/wordmark";

const links = [
  ["Plans", "/plans"],
  ["About", "/about"],
  ["How it works", "/how-it-works"],
  ["Investment approach", "/investment-approach"],
  ["Contact", "/contact"],
];

export function SiteHeader() {
  return (
    <header className="sticky top-0 z-20 border-b border-line bg-white">
      <div className="mx-auto flex h-16 max-w-content items-center justify-between px-5">
        <Wordmark />
        <nav className="hidden items-center gap-6 md:flex" aria-label="Primary">
          {links.map(([label, href]) => (
            <Link key={href} href={href} className="text-sm text-ink-muted hover:text-ink">
              {label}
            </Link>
          ))}
        </nav>
        <div className="hidden items-center gap-2 md:flex">
          <Link href="/login" className="rounded-lg px-3 py-2 text-sm text-ink hover:bg-muted">
            Sign in
          </Link>
          <Link href="/register" className="rounded-lg bg-brand px-3 py-2 text-sm text-white hover:bg-brand-hover">
            Create account
          </Link>
        </div>
        <details className="relative md:hidden">
          <summary className="cursor-pointer list-none rounded-lg border border-line px-3 py-2 text-sm">Menu</summary>
          <div className="absolute right-0 mt-2 w-56 rounded-card border border-line bg-white p-2 shadow-card">
            {links.map(([label, href]) => (
              <Link key={href} href={href} className="block rounded-lg px-3 py-2 text-sm hover:bg-muted">
                {label}
              </Link>
            ))}
            <Link href="/login" className="block rounded-lg px-3 py-2 text-sm hover:bg-muted">Sign in</Link>
            <Link href="/register" className="block rounded-lg px-3 py-2 text-sm text-brand">Create account</Link>
          </div>
        </details>
      </div>
    </header>
  );
}
