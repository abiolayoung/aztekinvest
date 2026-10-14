import { updateProfileAction } from "@/lib/actions/account";
import { StateForm } from "@/components/forms/state-form";
import { Input, Label, Select } from "@/components/ui/fields";
import { PageIntro } from "@/components/ui/page";
import { countries } from "@/lib/constants/countries";
import { requireUser } from "@/lib/auth/session";
import { accountStatusLabel, labelFor, verificationLabel } from "@/lib/format/labels";

export default async function ProfilePage() {
  const { profile, user } = await requireUser();
  const preferences = profile.notification_preferences ?? {};
  return (
    <div className="max-w-form">
      <PageIntro title="Profile and security" body="You can update your contact details. Role, verification, and balances cannot be edited here." />
      <dl className="mb-6 space-y-2 rounded-card border border-line bg-white p-4 text-sm">
        <div className="flex justify-between"><dt className="text-ink-muted">Email</dt><dd>{user.email}</dd></div>
        <div className="flex justify-between"><dt className="text-ink-muted">Email verification</dt><dd>{profile.email_verified_at ? "Verified" : "Not verified"}</dd></div>
        <div className="flex justify-between"><dt className="text-ink-muted">Account review</dt><dd>{labelFor(verificationLabel, profile.verification_status)}</dd></div>
        <div className="flex justify-between"><dt className="text-ink-muted">Status</dt><dd>{labelFor(accountStatusLabel, profile.account_status)}</dd></div>
      </dl>
      <StateForm action={updateProfileAction} submitLabel="Save profile">
        <div>
          <Label htmlFor="fullName">Full legal name</Label>
          <Input id="fullName" name="fullName" defaultValue={profile.full_name} required />
        </div>
        <div>
          <Label htmlFor="countryCode">Country of residence</Label>
          <Select id="countryCode" name="countryCode" defaultValue={profile.country_code ?? ""} required>
            {countries.map((country) => <option key={country.code} value={country.code}>{country.name}</option>)}
          </Select>
        </div>
        <div>
          <Label htmlFor="phone">Phone</Label>
          <Input id="phone" name="phone" defaultValue={profile.phone ?? ""} />
        </div>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" name="emailNotifications" defaultChecked={preferences.email !== false} />
          Email notifications
        </label>
      </StateForm>
      <p className="mt-6 text-sm text-ink-muted">To change your password, use the reset link on the sign-in page. Multi-factor authentication can be required for administrators before production use. It is not represented as enabled unless the authentication provider has enrolled a factor.</p>
    </div>
  );
}
