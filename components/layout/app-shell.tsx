import Link from "next/link";
import { signOutAction } from "@/lib/actions/auth";
import { Wordmark } from "@/components/brand/wordmark";
import { SideNav, type NavItem } from "@/components/layout/side-nav";

export function AppShell({
  items,
  title,
  homeHref,
  profileName,
  unread = 0,
  children,
}: {
  items: NavItem[];
  title: string;
  homeHref: string;
  profileName: string;
  unread?: number;
  children: React.ReactNode;
}) {
  const primary = items.slice(0, 4);
  return (
    <div className="min-h-screen bg-canvas md:grid md:grid-cols-[240px_1fr]">
      <aside className="sticky top-0 hidden h-screen flex-col border-r border-line bg-white px-4 py-5 md:flex">
        <Wordmark href={homeHref} />
        <div className="mt-8 flex-1">
          <SideNav items={items} label="Account" />
        </div>
        <form action={signOutAction}>
          <button className="w-full rounded-lg px-3 py-2 text-left text-sm text-ink-muted hover:bg-muted" type="submit">
            Sign out
          </button>
        </form>
      </aside>
      <div className="min-w-0">
        <header className="sticky top-0 z-20 flex h-14 items-center justify-between border-b border-line bg-white px-4 md:px-6">
          <div className="flex items-center gap-3">
            <div className="md:hidden">
              <Wordmark href={homeHref} compact />
            </div>
            <p className="hidden text-sm text-ink-muted md:block">{title}</p>
          </div>
          <div className="flex items-center gap-3 text-sm">
            <Link href={homeHref.startsWith("/admin") ? "/admin/notifications" : "/dashboard/notifications"} className="relative rounded-lg px-2 py-1 hover:bg-muted">
              Notifications
              {unread > 0 ? <span className="ml-1 rounded-full bg-brand px-1.5 text-xs text-white">{unread}</span> : null}
            </Link>
            <span className="max-w-40 truncate text-ink-muted">{profileName || "Account"}</span>
          </div>
        </header>
        <main className="mx-auto w-full max-w-content px-4 py-6 pb-24 md:px-6 md:pb-10">{children}</main>
        <nav className="fixed inset-x-0 bottom-0 z-20 grid grid-cols-5 border-t border-line bg-white md:hidden" aria-label="Mobile">
          {primary.map((item) => (
            <Link key={item.href} href={item.href} className="px-1 py-3 text-center text-[11px] text-ink">
              {item.label}
            </Link>
          ))}
          <details className="relative">
            <summary className="cursor-pointer list-none px-1 py-3 text-center text-[11px]">More</summary>
            <div className="absolute bottom-12 right-1 w-48 rounded-card border border-line bg-white p-2 shadow-card">
              {items.slice(4).map((item) => (
                <Link key={item.href} href={item.href} className="block rounded-lg px-3 py-2 text-sm hover:bg-muted">
                  {item.label}
                </Link>
              ))}
              <form action={signOutAction}>
                <button className="w-full rounded-lg px-3 py-2 text-left text-sm hover:bg-muted" type="submit">
                  Sign out
                </button>
              </form>
            </div>
          </details>
        </nav>
      </div>
    </div>
  );
}
