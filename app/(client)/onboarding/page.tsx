import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";
import { acknowledgeWelcomeAction, completeOnboardingAction, requestReviewAction, updateProfileAction } from "@/lib/actions/account";
import { signOutAction } from "@/lib/actions/auth";
import { isStaffRole } from "@/lib/auth/permissions";
import { requireUser } from "@/lib/auth/session";
import { countries } from "@/lib/constants/countries";
import { Wordmark } from "@/components/brand/wordmark";
import { StateForm } from "@/components/forms/state-form";
import { Input, Label, Select } from "@/components/ui/fields";
import { verificationLabel, labelFor } from "@/lib/format/labels";

export default async function OnboardingPage() {
  const { profile } = await requireUser();
  if (isStaffRole(profile.role)) redirect("/admin");
  if (profile.onboarding_completed_at) redirect("/dashboard");
  const step = !profile.onboarding_welcome_at ? 1 : profile.full_name && profile.country_code ? profile.verification_status === "unverified" ? 3 : 4 : 2;

  return (
    <main className="mx-auto min-h-screen max-w-form px-5 py-12">
      <Wordmark />
      <p className="mt-8 text-sm text-brand">Step {step} of 4</p>
      {step === 1 ? <Welcome /> : null}
      {step === 2 ? <ProfileForm profile={profile} /> : null}
      {step === 3 ? <Verification profile={profile} /> : null}
      {step === 4 ? <Ready profile={profile} /> : null}
      <form action={signOutAction} className="mt-8">
        <button className="text-sm text-ink-muted" type="submit">Sign out</button>
      </form>
    </main>
  );
}

function Welcome() {
  return (
    <section className="mt-3">
      <h1 className="text-2xl font-medium">Welcome</h1>
      <div className="mt-4 space-y-3 text-sm leading-6 text-ink-muted">
        <p>Aztek manages the investments. You fund the account, follow the records, and request withdrawals. You cannot place trades or choose instruments for direct execution.</p>
        <p>A deposit request does not credit your account. Credit happens only after payment verification. Portfolio performance appears only when verified valuations exist.</p>
      </div>
      <div className="mt-6">
        <StateForm action={acknowledgeWelcomeAction} submitLabel="Continue" pendingLabel="Saving...">
          <span className="sr-only">Continue after reading the overview.</span>
        </StateForm>
      </div>
    </section>
  );
}

function ProfileForm({ profile }: { profile: { full_name: string; country_code: string | null; phone: string | null } }) {
  return (
    <section className="mt-3">
      <h1 className="text-2xl font-medium">Complete profile</h1>
      <p className="mt-2 text-sm text-ink-muted">We do not collect identity documents in this portal.</p>
      <div className="mt-5">
        <StateForm action={updateProfileAction} submitLabel="Save profile">
          <div>
            <Label htmlFor="fullName">Full legal name</Label>
            <Input id="fullName" name="fullName" defaultValue={profile.full_name} required />
          </div>
          <div>
            <Label htmlFor="countryCode">Country of residence</Label>
            <Select id="countryCode" name="countryCode" defaultValue={profile.country_code ?? ""} required>
              <option value="" disabled>Choose a country</option>
              {countries.map((country) => <option key={country.code} value={country.code}>{country.name}</option>)}
            </Select>
          </div>
          <div>
            <Label htmlFor="phone">Phone, optional</Label>
            <Input id="phone" name="phone" defaultValue={profile.phone ?? ""} />
          </div>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" name="emailNotifications" defaultChecked />
            Email notifications
          </label>
        </StateForm>
      </div>
    </section>
  );
}

function Verification({ profile }: { profile: { email_verified_at: string | null; verification_status: string } }) {
  return (
    <section className="mt-3">
      <h1 className="text-2xl font-medium">Verification</h1>
      <ul className="mt-4 space-y-2 text-sm text-ink-muted">
        <li>Email: {profile.email_verified_at ? "Verified" : "Still required. Open the link sent to your inbox."}</li>
        <li>Identity review: {labelFor(verificationLabel, profile.verification_status)}. Email verification is not identity verification.</li>
      </ul>
      {profile.email_verified_at ? (
        <div className="mt-6">
          <StateForm action={requestReviewAction} submitLabel="Submit for review" pendingLabel="Submitting...">
            <span className="sr-only">Submit this account for review.</span>
          </StateForm>
        </div>
      ) : null}
    </section>
  );
}

function Ready({ profile }: { profile: { verification_status: string } }) {
  return (
    <section className="mt-3">
      <h1 className="text-2xl font-medium">Account ready</h1>
      <p className="mt-3 text-sm leading-6 text-ink-muted">
        Review status: {labelFor(verificationLabel, profile.verification_status)}. Deposits stay closed until the review is approved and an administrator has opened funding.
      </p>
      <div className="mt-6">
        <StateForm action={completeOnboardingAction} submitLabel="Go to your account" pendingLabel="Opening account...">
          <span className="sr-only">Finish setup and open the account.</span>
        </StateForm>
      </div>
    </section>
  );
}
