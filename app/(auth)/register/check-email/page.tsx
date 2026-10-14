import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = { title: "Check your email" };

export default function CheckEmailPage() {
  return (
    <div>
      <h1 className="text-2xl font-medium">Check your email</h1>
      <p className="mt-3 text-sm leading-6 text-ink-muted">
        Your account has been created. Open the verification link before funding. Email verification confirms the inbox. It is not proof of identity, and deposits stay unavailable until account review is approved.
      </p>
      <Link href="/login" className="mt-6 inline-flex text-sm text-brand">Return to sign in</Link>
    </div>
  );
}
