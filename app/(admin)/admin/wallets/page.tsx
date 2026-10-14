import { saveAssetAction } from "@/lib/actions/admin";
import { StateForm } from "@/components/forms/state-form";
import { Input, Label } from "@/components/ui/fields";
import { PageIntro } from "@/components/ui/page";
import { can } from "@/lib/auth/permissions";
import { requireUser } from "@/lib/auth/session";
import { formatUsdCents } from "@/lib/finance/money";

export default async function WalletsPage() {
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "manageWallets")) return <p>You do not have permission to configure wallets.</p>;
  const { data, error } = await supabase.rpc("admin_list_deposit_assets");
  const assets = Array.isArray(data) ? data : [];
  return (
    <div>
      <PageIntro title="Wallet configuration" body="Enter an address only after it has been verified outside this application. The portal does not generate addresses or store private keys. Deposits for an asset stay off until you mark the address verified and enable it." />
      {error ? <p className="mb-4 text-sm text-danger">Wallet configuration could not be loaded.</p> : null}
      <section className="mb-6 rounded-card border border-line bg-white p-4">
        <h2 className="mb-3 font-medium">Add asset and network</h2>
        <AssetForm />
      </section>
      <div className="space-y-4">
        {assets.map((asset) => (
          <section key={asset.id} className="rounded-card border border-line bg-white p-4">
            <h2 className="font-medium">{asset.symbol} · {asset.network_name}</h2>
            <p className="mt-1 text-xs text-ink-muted">Deposits {asset.deposit_enabled ? "enabled" : "disabled"} · minimum {formatUsdCents(asset.minimum_deposit_cents)} · maximum {asset.maximum_deposit_cents ? formatUsdCents(asset.maximum_deposit_cents) : "—"}</p>
            <div className="mt-3"><AssetForm asset={asset} /></div>
          </section>
        ))}
      </div>
    </div>
  );
}

function AssetForm({ asset }: { asset?: Record<string, string | number | boolean | null> }) {
  const formKey = String(asset?.id ?? "new");
  return (
    <StateForm action={saveAssetAction} submitLabel={asset ? "Update configuration" : "Save configuration"}>
      <input type="hidden" name="assetId" value={String(asset?.id ?? "")} />
      <div className="grid gap-3 md:grid-cols-2">
        <Field formKey={formKey} name="symbol" label="Symbol" defaultValue={String(asset?.symbol ?? "")} />
        <Field formKey={formKey} name="assetName" label="Asset name" defaultValue={String(asset?.asset_name ?? "")} />
        <Field formKey={formKey} name="networkName" label="Network name" defaultValue={String(asset?.network_name ?? "")} />
        <Field formKey={formKey} name="networkIdentifier" label="Network identifier" defaultValue={String(asset?.network_identifier ?? "")} />
        <Field formKey={formKey} name="assetContract" label="Asset contract, if any" defaultValue={String(asset?.asset_contract ?? "")} />
        <Field formKey={formKey} name="receivingAddress" label="Receiving address" defaultValue={String(asset?.receiving_address ?? "")} />
        <Field formKey={formKey} name="minimum" label="Minimum deposit USD" defaultValue={asset ? centsToInput(asset.minimum_deposit_cents) : ""} />
        <Field formKey={formKey} name="maximum" label="Maximum deposit USD" defaultValue={asset?.maximum_deposit_cents ? centsToInput(asset.maximum_deposit_cents) : ""} />
        <Field formKey={formKey} name="requiredConfirmations" label="Required confirmations" defaultValue={String(asset?.required_confirmations ?? 12)} />
        <Field formKey={formKey} name="withdrawalFee" label="Withdrawal fee USD" defaultValue={asset?.withdrawal_fee_cents ? centsToInput(asset.withdrawal_fee_cents) : ""} />
        <Field formKey={formKey} name="custodyProvider" label="Custody provider" defaultValue={String(asset?.custody_provider ?? "")} />
        <Field formKey={formKey} name="decimals" label="Display decimals" defaultValue={String(asset?.decimals ?? 6)} />
      </div>
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="addressIsShared" defaultChecked={asset ? Boolean(asset.address_is_shared) : true} />Address may be shared</label>
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="addressVerified" defaultChecked={Boolean(asset?.address_verified_at)} />I have verified this receiving address out of band</label>
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="depositEnabled" defaultChecked={Boolean(asset?.deposit_enabled)} />Enable deposits</label>
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="withdrawalEnabled" defaultChecked={Boolean(asset?.withdrawal_enabled)} />Enable withdrawals</label>
    </StateForm>
  );
}

function Field({ formKey, name, label, defaultValue }: { formKey: string; name: string; label: string; defaultValue: string }) {
  const id = `${formKey}-${name}`;
  return (
    <div>
      <Label htmlFor={id}>{label}</Label>
      <Input id={id} name={name} defaultValue={defaultValue} />
    </div>
  );
}

function centsToInput(value: string | number | boolean | null): string {
  const cents = BigInt(String(value ?? 0));
  const negative = cents < 0n;
  const absolute = negative ? -cents : cents;
  return `${negative ? "-" : ""}${absolute / 100n}.${(absolute % 100n).toString().padStart(2, "0")}`;
}
