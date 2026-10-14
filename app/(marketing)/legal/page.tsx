import type { Metadata } from "next";

export const metadata: Metadata = { title: "Legal and disclosures" };

export default function LegalPage() {
  return (
    <main className="mx-auto max-w-3xl space-y-8 px-5 py-14 text-sm leading-7 text-ink-muted">
      <div>
        <h1 className="text-3xl font-medium tracking-tight text-ink">Legal and disclosures</h1>
        <p className="mt-3">
          Approved legal text has not been published in this application. Do not fund an account until you have reviewed the final terms, privacy notice, and risk disclosures issued by Aztek.
        </p>
      </div>
      <section>
        <h2 className="text-xl font-medium text-ink">Terms of service</h2>
        <p className="mt-2">The operating terms, fees, eligibility rules, and complaints procedure must be supplied by the company before real-money use. This page is a placeholder for that approved text.</p>
      </section>
      <section id="privacy">
        <h2 className="text-xl font-medium text-ink">Privacy policy</h2>
        <p className="mt-2">Account data is stored so Aztek can operate the client record. A privacy notice describing categories of data, retention, and rights has not yet been configured. Do not submit identity documents through this portal. The application does not ask for them.</p>
      </section>
      <section id="risk">
        <h2 className="text-xl font-medium text-ink">Investment risk disclosure</h2>
        <p className="mt-2">Investments can lose value, including the possibility of losing the amount invested. Past records are not a guide to future results. Nothing in the portal is a guarantee of profit, income, or capital protection. Performance is shown only when the valuation history is sufficient. Otherwise the portal says that it is not yet available.</p>
      </section>
      <section id="crypto">
        <h2 className="text-xl font-medium text-ink">Cryptocurrency deposit disclosure</h2>
        <p className="mt-2">A cryptocurrency transfer can be irreversible. You must send the selected asset on the selected network only. The amount you type is a request, not proof that funds arrived. A transaction hash helps the review. It does not by itself credit the account. Deposits remain unavailable until an administrator verifies a receiving address and opens funding. This application does not generate wallet addresses and does not store private keys.</p>
      </section>
      <section>
        <h2 className="text-xl font-medium text-ink">Jurisdiction</h2>
        <p className="mt-2">The operating jurisdiction and any regulatory authorization are not configured. This application does not claim a license, membership, insurance, or regulatory approval.</p>
      </section>
    </main>
  );
}
