import type { Metadata } from "next";

export const metadata: Metadata = { title: "About" };

const principles = [
  ["Professional investment management", "Investment execution stays with authorized Aztek personnel. Clients use the portal to fund, monitor, and request withdrawals."],
  ["Transparency and accountability", "Deposits, ledger entries, investment records, and administrative decisions are stored as an auditable history."],
  ["Research-driven decisions", "The investment approach is built around research and portfolio oversight rather than client-directed trading."],
  ["Diversification and oversight", "Accounts can hold cash and recorded managed holdings. A transfer into an investment changes the mix of the account. It does not itself create a profit."],
  ["Ethical conduct and confidentiality", "Clients can see their own records. They cannot view another client's information or change their own role."],
  ["Clear communication about risk", "The portal states when a valuation is missing and does not present a percentage return without sufficient history."],
];

export default function AboutPage() {
  return (
    <main className="mx-auto max-w-3xl px-5 py-14">
      <p className="text-sm text-brand">About Aztek</p>
      <h1 className="mt-2 text-3xl font-medium tracking-tight">Investment management with a clear account record.</h1>
      <p className="mt-4 text-sm leading-7 text-ink-muted">
        Aztek Investment Company provides a managed investment relationship. This portal is the client record of that relationship: funding, balances, recorded investment activity, and withdrawal requests. Company registration, regulatory status, and office details are shown only after they have been verified and configured. None are claimed here.
      </p>
      <div className="mt-8 space-y-4">
        {principles.map(([title, body]) => (
          <section key={title} className="rounded-card border border-line bg-white p-5">
            <h2 className="text-lg font-medium">{title}</h2>
            <p className="mt-2 text-sm leading-6 text-ink-muted">{body}</p>
          </section>
        ))}
      </div>
    </main>
  );
}
