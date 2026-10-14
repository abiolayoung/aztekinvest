import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = { title: "How it works" };

const steps = [
  ["Create an account", "Register with your legal name, email, password, and country. The registration form cannot assign an administrator role."],
  ["Verify your email and profile", "Email verification confirms control of the inbox. It is not identity verification. Funding stays closed until the required review is approved."],
  ["Submit a deposit", "Choose an enabled cryptocurrency and network, review the instructions, and create a request. A request is not a credit."],
  ["Wait for payment verification", "Submit the transaction hash after you send funds. An administrator verifies the transfer before any amount is credited. A screenshot is not enough."],
  ["Monitor the managed account", "Confirmed cash, recorded allocations, valuations, fees, and withdrawals appear from the ledger and investment records. You cannot place trades."],
  ["Request a withdrawal", "If withdrawals are open, you can request an amount up to the available cash balance. The request is reviewed before any payout is marked complete."],
];

export default function HowItWorksPage() {
  return (
    <main className="mx-auto max-w-3xl px-5 py-14">
      <h1 className="text-3xl font-medium tracking-tight">How it works</h1>
      <p className="mt-3 text-sm leading-7 text-ink-muted">
        The sequence is deliberate. Money moves only when a recorded verification or investment action says it does.
      </p>
      <ol className="mt-8 list-none space-y-4">
        {steps.map(([title, body], index) => (
          <li key={title} className="rounded-card border border-line bg-white p-5">
            <p className="text-xs text-brand">Step {index + 1}</p>
            <h2 className="mt-1 text-lg font-medium">{title}</h2>
            <p className="mt-2 text-sm leading-6 text-ink-muted">{body}</p>
          </li>
        ))}
      </ol>
      <Link href="/register" className="mt-8 inline-flex rounded-lg bg-brand px-4 py-3 text-sm text-white">
        Create your account
      </Link>
    </main>
  );
}
