"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createDepositAction } from "@/lib/actions/deposits";
import { formatUsdCents, parseUsdToCents } from "@/lib/finance/money";
import { Button } from "@/components/ui/button";
import { FormAlert, Input, Label } from "@/components/ui/fields";

export type DepositAssetOption = {
  id: string;
  symbol: string;
  asset_name: string;
  network_name: string;
  network_identifier: string;
  minimum_deposit_cents: string | number;
  maximum_deposit_cents: string | number | null;
  required_confirmations: number;
  address_is_shared: boolean;
};

export function DepositWizard({ assets }: { assets: DepositAssetOption[] }) {
  const router = useRouter();
  const [step, setStep] = useState(0);
  const [amount, setAmount] = useState("");
  const [symbol, setSymbol] = useState("");
  const [assetId, setAssetId] = useState("");
  const [acknowledged, setAcknowledged] = useState(false);
  const [error, setError] = useState<string>();
  const [pending, setPending] = useState(false);
  const [idempotencyKey] = useState(() => crypto.randomUUID());

  const symbolOptions = useMemo(() => {
    const map = new Map<string, { symbol: string; asset_name: string; networks: DepositAssetOption[] }>();
    for (const asset of assets) {
      const existing = map.get(asset.symbol);
      if (existing) existing.networks.push(asset);
      else map.set(asset.symbol, { symbol: asset.symbol, asset_name: asset.asset_name, networks: [asset] });
    }
    return [...map.values()].sort((a, b) => a.symbol.localeCompare(b.symbol));
  }, [assets]);

  const networks = assets.filter((asset) => asset.symbol === symbol);
  const selected = assets.find((asset) => asset.id === assetId);
  const cents = parseUsdToCents(amount);

  function chooseSymbol(nextSymbol: string) {
    setSymbol(nextSymbol);
    setAssetId("");
    const matches = assets.filter((asset) => asset.symbol === nextSymbol);
    if (matches.length === 1) setAssetId(matches[0].id);
  }

  function next() {
    setError(undefined);
    if (step === 0 && !cents) {
      setError("Enter an amount in dollars and cents.");
      return;
    }
    if (step === 1 && !symbol) {
      setError("Choose whether you will pay with Bitcoin or USDT.");
      return;
    }
    if (step === 2 && !selected) {
      setError("Choose the exact network. USDT on the wrong network can be lost.");
      return;
    }
    setStep((value) => value + 1);
  }

  async function submit() {
    if (!selected || !acknowledged) {
      setError("Confirm that you understand the transfer cannot be reversed by Aztek.");
      return;
    }
    setPending(true);
    const result = await createDepositAction({
      amount,
      assetId: selected.id,
      idempotencyKey,
      riskAcknowledged: acknowledged,
    });
    setPending(false);
    if (!result.ok) {
      setError(result.error);
      return;
    }
    router.push(`/dashboard/deposits/${result.id}`);
  }

  return (
    <div className="mx-auto max-w-form space-y-5">
      <ol className="grid list-none grid-cols-4 gap-2 text-xs text-ink-muted">
        {["Amount", "Pay with", "Network", "Review"].map((label, index) => (
          <li key={label} className={index === step ? "font-medium text-brand" : undefined} aria-current={index === step ? "step" : undefined}>
            {index + 1}. {label}
          </li>
        ))}
      </ol>
      <FormAlert error={error} />

      {step === 0 ? (
        <div>
          <Label htmlFor="amount">Amount in USD</Label>
          <Input id="amount" inputMode="decimal" value={amount} onChange={(event) => setAmount(event.target.value)} placeholder="0.00" />
          <p className="mt-2 text-sm text-ink-muted">
            Enter how much you want to deposit in USD. On the next screens you will choose Bitcoin or USDT, then see the wallet details.
          </p>
        </div>
      ) : null}

      {step === 1 ? (
        <div className="space-y-3">
          <p className="text-sm text-ink-muted">
            Choose how you want to pay. Payment details and the receiving wallet are shown only after you create the deposit request.
          </p>
          {symbolOptions.map((option) => (
            <button
              key={option.symbol}
              type="button"
              onClick={() => chooseSymbol(option.symbol)}
              className={`w-full rounded-card border px-4 py-4 text-left transition ${
                symbol === option.symbol ? "border-brand bg-muted" : "border-line bg-white hover:bg-muted/60"
              }`}
            >
              <span className="text-base font-medium">{option.symbol}</span>
              <span className="mt-1 block text-sm text-ink">{option.asset_name}</span>
              <span className="mt-2 block text-sm text-ink-muted">
                Available network{option.networks.length === 1 ? "" : "s"}:{" "}
                {option.networks.map((network) => network.network_name).join(", ")}
              </span>
            </button>
          ))}
        </div>
      ) : null}

      {step === 2 ? (
        <div className="space-y-3">
          <div className="rounded-lg border border-warning/30 bg-muted px-3 py-2 text-sm text-ink">
            Send <strong className="font-medium">{symbol}</strong> only on the network you select below. A transfer on another network can be permanently lost.
          </div>
          {networks.map((asset) => (
            <button
              key={asset.id}
              type="button"
              onClick={() => setAssetId(asset.id)}
              className={`w-full rounded-card border px-4 py-4 text-left transition ${
                assetId === asset.id ? "border-brand bg-muted" : "border-line bg-white hover:bg-muted/60"
              }`}
            >
              <span className="text-base font-medium">{asset.network_name}</span>
              <span className="mt-1 block text-sm text-ink-muted">Network identifier: {asset.network_identifier}</span>
              {asset.symbol === "USDT" && asset.network_identifier.toLowerCase().includes("bnb") ? (
                <span className="mt-2 block text-sm font-medium text-brand">
                  Use BNB Smart Chain / BEP20 only. Do not send USDT on ERC20, TRC20, or any other network.
                </span>
              ) : null}
              {asset.symbol === "BTC" ? (
                <span className="mt-2 block text-sm font-medium text-brand">Use the Bitcoin network only.</span>
              ) : null}
              <span className="mt-2 block text-sm text-ink-muted">
                Limits: {formatUsdCents(asset.minimum_deposit_cents)} to {formatUsdCents(asset.maximum_deposit_cents)}
              </span>
            </button>
          ))}
        </div>
      ) : null}

      {step === 3 && selected ? (
        <div className="space-y-3 rounded-card border border-line bg-white p-4 text-sm">
          <Row label="Requested amount" value={cents ? formatUsdCents(cents) : "—"} />
          <Row label="Pay with" value={`${selected.symbol} · ${selected.asset_name}`} />
          <Row label="Network" value={`${selected.network_name} (${selected.network_identifier})`} />
          <Row label="Wallet details" value="Shown on the next screen after you create this request" />
          <Row label="Estimated crypto amount" value="Not quoted. Send the USD equivalent using your wallet." />
          <Row label="Fees" value="Network fees are paid by you in your wallet. Aztek does not add a deposit fee here." />
          <p className="rounded-lg bg-muted px-3 py-2 text-ink-muted">
            After you continue, you will see the receiving wallet address and QR code. Do not send funds until that screen is open and you have checked the network.
          </p>
          <label className="flex items-start gap-2">
            <input type="checkbox" className="mt-1" checked={acknowledged} onChange={(event) => setAcknowledged(event.target.checked)} />
            <span>
              I understand cryptocurrency transfers can be irreversible, and I must send {selected.symbol} on{" "}
              {selected.network_name} only.
            </span>
          </label>
        </div>
      ) : null}

      <div className="flex gap-2">
        {step > 0 ? (
          <Button type="button" variant="secondary" onClick={() => setStep((value) => value - 1)}>
            Back
          </Button>
        ) : null}
        {step < 3 ? (
          <Button type="button" onClick={next}>
            Continue
          </Button>
        ) : (
          <Button type="button" onClick={submit} disabled={pending}>
            {pending ? "Creating request..." : "Continue to payment details"}
          </Button>
        )}
      </div>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start justify-between gap-4">
      <span className="text-ink-muted">{label}</span>
      <span className="numeric text-right">{value}</span>
    </div>
  );
}
