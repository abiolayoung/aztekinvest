import type { Metadata } from "next";
import { resetPasswordAction } from "@/lib/actions/auth";
import { StateForm } from "@/components/forms/state-form";
import { Input, Label } from "@/components/ui/fields";

export const metadata: Metadata = { title: "Choose a new password" };

export default function ResetPasswordPage() {
  return (
    <div>
      <h1 className="text-2xl font-medium">Choose a new password</h1>
      <div className="mt-6">
        <StateForm action={resetPasswordAction} submitLabel="Update password" pendingLabel="Updating...">
          <div>
            <Label htmlFor="password">New password</Label>
            <Input id="password" name="password" type="password" autoComplete="new-password" required />
          </div>
          <div>
            <Label htmlFor="confirmPassword">Confirm password</Label>
            <Input id="confirmPassword" name="confirmPassword" type="password" autoComplete="new-password" required />
          </div>
        </StateForm>
      </div>
    </div>
  );
}
