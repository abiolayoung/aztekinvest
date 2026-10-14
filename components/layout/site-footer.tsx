import Link from "next/link";

export function SiteFooter({ supportEmail }: { supportEmail?: string | null }) {
  return (
    <footer className="border-t border-line bg-white">
      <div className="mx-auto grid max-w-content gap-8 px-5 py-10 md:grid-cols-3">
        <div>
          <p className="text-sm font-medium text-ink">Aztek Investment Company</p>
          <p className="mt-2 text-sm leading-6 text-ink-muted">
            Managed investment accounts with research, diversification, and clear reporting. Investment values can fall as well as rise.
          </p>
        </div>
        <div className="text-sm leading-7 text-ink-muted">
          <p className="font-medium text-ink">Contact</p>
          <p>{supportEmail || "Contact details have not been published yet."}</p>
        </div>
        <div className="flex flex-col text-sm leading-7 text-ink-muted">
          <Link href="/legal">Terms of service</Link>
          <Link href="/legal#privacy">Privacy policy</Link>
          <Link href="/legal#risk">Investment risk disclosure</Link>
          <Link href="/legal#crypto">Cryptocurrency deposit disclosure</Link>
        </div>
      </div>
    </footer>
  );
}
