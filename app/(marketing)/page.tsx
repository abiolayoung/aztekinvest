import Link from "next/link";
import type { Metadata } from "next";
import { PlanTrigger } from "@/components/plans/plan-trigger";
import { PricingSection } from "@/components/plans/pricing-section";

export const metadata: Metadata = { title: "A clearer view of your investments" };

const steps = [
  "Create an account.",
  "Complete the required verification.",
  "Submit a deposit.",
  "Wait for payment verification.",
  "Monitor your managed portfolio.",
];

export default function HomePage() {
  return (
    <main>
      <section className="mx-auto grid max-w-content items-center gap-12 px-5 py-16 lg:grid-cols-[1.1fr_0.9fr] lg:py-24">
        <div>
          <p className="text-sm font-medium text-brand">Managed investment accounts</p>
          <h1 className="mt-3 max-w-xl text-4xl font-medium tracking-tight text-ink">A clearer view of your investments.</h1>
          <p className="mt-4 max-w-xl text-base leading-7 text-ink-muted">
            Aztek combines research-driven investment management with transparent account reporting, giving you a clear view of your deposits, managed portfolio, and account activity.
          </p>
          <div className="mt-8 flex flex-wrap gap-3">
            <PlanTrigger className="rounded-lg bg-brand px-4 py-3 text-sm text-white hover:bg-brand-hover">
              View plans & sign up
            </PlanTrigger>
            <Link href="/how-it-works" className="rounded-lg border border-line bg-white px-4 py-3 text-sm text-ink hover:bg-muted">
              How it works
            </Link>
          </div>
        </div>
        <div className="rounded-card border border-line bg-white p-5 shadow-card" aria-label="Interface preview">
          <div className="flex items-center justify-between">
            <p className="text-sm font-medium">Account overview</p>
            <p className="text-xs text-ink-muted">Interface preview</p>
          </div>
          <p className="mt-1 text-xs text-ink-muted">Figures appear after real account records exist. This preview does not show client funds or performance.</p>
          <div className="mt-5 grid grid-cols-2 gap-3">
            {["Total account value", "Confirmed deposits", "Currently invested", "Portfolio performance"].map((label) => (
              <div key={label} className="rounded-lg bg-muted p-3">
                <p className="text-xs text-ink-muted">{label}</p>
                <p className="numeric mt-2 text-lg">{label === "Portfolio performance" ? "Not yet available" : "—"}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <PricingSection />

      <section className="mx-auto grid max-w-content gap-4 px-5 py-16 md:grid-cols-2">
        {[
          ["Managed by an investment team", "Authorized Aztek personnel manage investment execution. Clients monitor their accounts. The portal does not provide trading controls."],
          ["A simple way to fund your account", "When a cryptocurrency and network have been configured, you can request a deposit, follow the payment instructions, and submit a transaction hash for review."],
          ["Understand your portfolio", "Confirmed cash, recorded holdings, broker-recorded activity, and valuation history are shown from the account records. Pending deposits are not treated as credited funds."],
          ["Research and risk awareness", "Investment decisions are approached through research, diversification, and the client's objectives. Values can rise or fall, and no return is guaranteed."],
        ].map(([title, body]) => (
          <article key={title} className="rounded-card border border-line bg-white p-5">
            <h2 className="text-lg font-medium">{title}</h2>
            <p className="mt-2 text-sm leading-6 text-ink-muted">{body}</p>
          </article>
        ))}
      </section>

      <section className="border-y border-line bg-white">
        <div className="mx-auto max-w-content px-5 py-14">
          <h2 className="text-2xl font-medium">How it works</h2>
          <ol className="mt-6 grid list-none gap-4 md:grid-cols-5">
            {steps.map((step, index) => (
              <li key={step} className="rounded-card border border-line p-4">
                <p className="text-xs text-brand">0{index + 1}</p>
                <p className="mt-2 text-sm">{step}</p>
              </li>
            ))}
          </ol>
        </div>
      </section>

      <section className="mx-auto max-w-content px-5 py-14">
        <h2 className="text-2xl font-medium">Important investment information</h2>
        <p className="mt-3 max-w-3xl text-sm leading-6 text-ink-muted">
          Investment values can rise or fall. Cryptocurrency transfers can be irreversible. Fees, withdrawal conditions, and risks should be reviewed before funding an account. Aztek does not promise profits, capital protection, or a fixed withdrawal time.
        </p>
      </section>
    </main>
  );
}
