import type { Metadata } from "next";
import Link from "next/link";
import { forgotPasswordAction } from "@/lib/actions/auth";
import { StateForm } from "@/components/forms/state-form";
import { Input, Label } from "@/components/ui/fields";

export const metadata: Metadata = { title: "Password recovery" };

export default function ForgotPasswordPage() {
  return (
    <div>
      <h1 className="text-2xl font-medium">Reset password</h1>
      <p className="mt-1 text-sm text-ink-muted">We will send a reset link if the email belongs to an account.</p>
      <div className="mt-6">
        <StateForm action={forgotPasswordAction} submitLabel="Send reset link" pendingLabel="Sending...">
          <div>
            <Label htmlFor="email">Email</Label>
            <Input id="email" name="email" type="email" autoComplete="email" required />
          </div>
        </StateForm>
      </div>
      <Link href="/login" className="mt-4 inline-flex text-sm text-brand">Back to sign in</Link>
    </div>
  );
}
