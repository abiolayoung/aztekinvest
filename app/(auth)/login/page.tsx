import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { loginAction } from "@/lib/actions/auth";
import { homeForRole, getSession } from "@/lib/auth/session";
import { StateForm } from "@/components/forms/state-form";
import { FormAlert, Input, Label } from "@/components/ui/fields";

export const metadata: Metadata = { title: "Sign in" };

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string; reset?: string; registered?: string }>;
}) {
  const params = await searchParams;
  const session = await getSession();
  if (session.user && session.profile) {
    redirect(homeForRole(session.profile.role, Boolean(session.profile.onboarding_completed_at)));
  }
  return (
    <div>
      <h1 className="text-2xl font-medium">Sign in</h1>
      <p className="mt-1 text-sm text-ink-muted">Use the email and password for your Aztek account.</p>
      <div className="mt-6">
        {params.reset ? <div className="mb-4"><FormAlert message="Password updated. Sign in with the new password." /></div> : null}
        {params.registered ? <div className="mb-4"><FormAlert message="Your account was created. Sign in to continue." /></div> : null}
        <StateForm action={loginAction} submitLabel="Sign in" pendingLabel="Signing in...">
          <input type="hidden" name="next" value={params.next ?? ""} />
          <div>
            <Label htmlFor="email">Email</Label>
            <Input id="email" name="email" type="email" autoComplete="email" required />
          </div>
          <div>
            <Label htmlFor="password">Password</Label>
            <Input id="password" name="password" type="password" autoComplete="current-password" required />
          </div>
        </StateForm>
      </div>
      <div className="mt-4 flex justify-between text-sm">
        <Link href="/forgot-password" className="text-brand">Forgot password</Link>
        <Link href="/register" className="text-ink-muted">Create account</Link>
      </div>
    </div>
  );
}
