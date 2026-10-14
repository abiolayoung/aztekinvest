import { settingsAction } from "@/lib/actions/admin";
import { StateForm } from "@/components/forms/state-form";
import { Input, Label, Textarea } from "@/components/ui/fields";
import { PageIntro } from "@/components/ui/page";
import { can } from "@/lib/auth/permissions";
import { requireUser } from "@/lib/auth/session";

export default async function SettingsPage() {
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "manageSettings")) return <p>You do not have permission to change settings.</p>;
  const { data } = await supabase.from("app_settings").select("*").eq("id", 1).maybeSingle();
  return (
    <div className="max-w-form">
      <PageIntro title="Application settings" body="Deposits and withdrawals stay closed until you enable them here and configure a verified wallet." />
      <ul className="mb-4 space-y-1 text-sm text-ink-muted">
        <li>Email provider: {process.env.EMAIL_PROVIDER_API_KEY && process.env.EMAIL_FROM ? "configured" : "not configured"}</li>
        <li>Crypto monitoring provider: {process.env.CRYPTO_PROVIDER_WEBHOOK_SECRET ? "configured" : "not configured"}</li>
        <li>Service role for webhooks: {process.env.SUPABASE_SERVICE_ROLE_KEY ? "configured" : "not configured"}</li>
      </ul>
      <StateForm action={settingsAction} submitLabel="Save settings">
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="depositsEnabled" defaultChecked={Boolean(data?.deposits_enabled)} />Deposits enabled</label>
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="withdrawalsEnabled" defaultChecked={Boolean(data?.withdrawals_enabled)} />Withdrawals enabled</label>
        <div>
          <Label htmlFor="supportEmail">Published support email</Label>
          <Input id="supportEmail" name="supportEmail" defaultValue={data?.support_email ?? ""} />
        </div>
        <div>
          <Label htmlFor="depositNotificationEmail">Deposit review mailbox</Label>
          <Input id="depositNotificationEmail" name="depositNotificationEmail" defaultValue={data?.deposit_notification_email ?? ""} />
        </div>
        <div>
          <Label htmlFor="depositExpiryHours">Deposit request expiry, hours</Label>
          <Input id="depositExpiryHours" name="depositExpiryHours" defaultValue={String(data?.deposit_expiry_hours ?? 168)} />
        </div>
        <div>
          <Label htmlFor="withdrawalNotice">Withdrawal processing notice</Label>
          <Textarea id="withdrawalNotice" name="withdrawalNotice" defaultValue={data?.withdrawal_processing_notice ?? ""} />
        </div>
      </StateForm>
    </div>
  );
}
