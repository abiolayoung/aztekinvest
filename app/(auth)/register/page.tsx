import type { Metadata } from "next";
import Link from "next/link";
import { registerAction } from "@/lib/actions/auth";
import { countries } from "@/lib/constants/countries";
import { StateForm } from "@/components/forms/state-form";
import { Input, Label, Select } from "@/components/ui/fields";

export const metadata: Metadata = { title: "Create account" };

export default function RegisterPage() {
  return (
    <div>
      <h1 className="text-2xl font-medium">Create account</h1>
      <p className="mt-1 text-sm text-ink-muted">Registration creates a client profile. It cannot grant administrator access.</p>
      <div className="mt-6">
        <StateForm action={registerAction} submitLabel="Create account" pendingLabel="Creating account...">
          <div>
            <Label htmlFor="fullName">Full legal name</Label>
            <Input id="fullName" name="fullName" autoComplete="name" required />
          </div>
          <div>
            <Label htmlFor="email">Email address</Label>
            <Input id="email" name="email" type="email" autoComplete="email" required />
          </div>
          <div>
            <Label htmlFor="password">Password</Label>
            <Input id="password" name="password" type="password" autoComplete="new-password" required />
            <p className="mt-1 text-xs text-ink-muted">At least 12 characters, with upper and lower case, a number, and a symbol.</p>
          </div>
          <div>
            <Label htmlFor="confirmPassword">Confirm password</Label>
            <Input id="confirmPassword" name="confirmPassword" type="password" autoComplete="new-password" required />
          </div>
          <div>
            <Label htmlFor="countryCode">Country of residence</Label>
            <Select id="countryCode" name="countryCode" defaultValue="" required>
              <option value="" disabled>Choose a country</option>
              {countries.map((country) => (
                <option key={country.code} value={country.code}>{country.name}</option>
              ))}
            </Select>
          </div>
          <label className="flex items-start gap-2 text-sm">
            <input className="mt-1" type="checkbox" name="acceptTerms" required />
            <span>I accept the <Link href="/legal" className="text-brand">terms and privacy notice</Link>, including the statement that approved legal text may still be pending.</span>
          </label>
        </StateForm>
      </div>
      <p className="mt-4 text-sm text-ink-muted">Already registered? <Link href="/login" className="text-brand">Sign in</Link></p>
    </div>
  );
}
