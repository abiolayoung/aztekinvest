import { DepositWizard } from "@/components/deposits/deposit-wizard";
import { EmptyState, PageIntro } from "@/components/ui/page";
import { requireUser } from "@/lib/auth/session";

export default async function DepositPage() {
  const { supabase, profile } = await requireUser();
  const { data: settings } = await supabase.rpc("get_public_settings");
  const setting = Array.isArray(settings) ? settings[0] : settings;

  const listed = await supabase.rpc("list_enabled_deposit_assets");
  let options = Array.isArray(listed.data) ? listed.data : [];
  if (listed.error || options.length === 0) {
    const fallback = await supabase
      .from("deposit_assets")
      .select(
        "id, symbol, asset_name, network_name, network_identifier, minimum_deposit_cents, maximum_deposit_cents, required_confirmations, address_is_shared, deposit_enabled",
      )
      .eq("deposit_enabled", true);
    options = fallback.data ?? [];
  }

  const fundingOpen =
    Boolean(profile.email_verified_at) &&
    profile.verification_status === "verified" &&
    profile.account_status === "active";
  const depositsOpen = Boolean(setting?.deposits_enabled);

  return (
    <div>
      <PageIntro
        title="Make a deposit"
        body="Choose an amount, then choose Bitcoin or USDT. Wallet details and the QR code appear only after you create the request. Your account is credited after payment verification."
      />
      {!fundingOpen ? (
        <EmptyState title="Funding is not open for this account" body={missingFundingReason(profile)} />
      ) : !depositsOpen || options.length === 0 ? (
        <EmptyState
          title="Cryptocurrency deposits are not available yet"
          body="An administrator must verify a receiving address, set deposit limits, and open funding. No wallet address is shown until that configuration exists."
        />
      ) : (
        <DepositWizard assets={options} />
      )}
    </div>
  );
}

function missingFundingReason(profile: {
  email_verified_at: string | null;
  verification_status: string;
  account_status: string;
}): string {
  const missing = [
    !profile.email_verified_at ? "email verification" : null,
    profile.verification_status !== "verified" ? "account approval" : null,
    profile.account_status !== "active" ? "an active account status" : null,
  ].filter(Boolean);
  return `Still required: ${missing.join(", ")}.`;
}
