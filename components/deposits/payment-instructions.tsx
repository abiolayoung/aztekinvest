import { CopyButton } from "@/components/deposits/copy-button";
import { Money } from "@/components/ui/page";

type PaymentInstructionsProps = {
  reference: string;
  address: string;
  assetSymbol: string;
  assetName: string;
  networkName: string;
  networkIdentifier: string;
  requestedAmountCents: string | number | bigint;
  qrSrc: string | null;
  addressIsShared: boolean;
};

export function PaymentInstructions({
  reference,
  address,
  assetSymbol,
  assetName,
  networkName,
  networkIdentifier,
  requestedAmountCents,
  qrSrc,
  addressIsShared,
}: PaymentInstructionsProps) {
  return (
    <section className="mt-4 space-y-4 rounded-card border border-line bg-white p-5">
      <div>
        <h2 className="text-base font-medium">How to pay</h2>
        <p className="mt-1 text-sm leading-6 text-ink-muted">
          Follow every step below. Send only {assetSymbol} on {networkName}. Sending the wrong asset or network can result in irreversible loss.
        </p>
      </div>

      <ol className="list-none space-y-4">
        <Step number="1" title="Confirm the amount, asset, and network">
          <p>
            You requested <Money cents={requestedAmountCents} /> in USD terms. Pay with{" "}
            <strong className="font-medium text-ink">{assetName} ({assetSymbol})</strong> on{" "}
            <strong className="font-medium text-ink">{networkName}</strong>.
          </p>
          <p className="mt-2 rounded-lg border border-brand/20 bg-muted px-3 py-2 text-sm">
            Required network: <strong className="font-medium text-ink">{networkName}</strong>
            <span className="mt-1 block text-ink-muted">Network identifier: {networkIdentifier}</span>
          </p>
          {assetSymbol === "USDT" && /bnb|bsc|bep20/i.test(networkIdentifier + networkName) ? (
            <p className="mt-2 text-sm font-medium text-brand">
              This is BNB Smart Chain (BEP20) only. Do not send USDT on ERC20, TRC20, Solana, or any other network.
            </p>
          ) : null}
          {assetSymbol === "BTC" ? (
            <p className="mt-2 text-sm font-medium text-brand">Send Bitcoin on the Bitcoin network only.</p>
          ) : null}
        </Step>

        <Step number="2" title="Scan the QR code or copy the wallet address">
          <p className="mb-3">
            Open your {assetSymbol} wallet app. Scan the QR code, or copy the address and paste it as the destination.
          </p>
          {qrSrc ? (
            <div className="flex flex-col items-start gap-3 sm:flex-row sm:items-center">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={qrSrc}
                alt={`${assetSymbol} receiving wallet QR code`}
                className="h-48 w-48 rounded-lg border border-line bg-white object-contain p-2"
              />
              <div className="space-y-2 text-sm text-ink-muted">
                <p>Use your wallet app camera or QR scanner.</p>
                <p>Double-check that the address in your wallet matches the address shown here before you send.</p>
              </div>
            </div>
          ) : null}
          <div className="mt-4 rounded-lg bg-muted p-3">
            <p className="text-xs font-medium uppercase tracking-wide text-ink-muted">Receiving wallet address</p>
            <p className="mt-2 break-all font-mono text-sm text-ink">{address}</p>
            <div className="mt-3 flex flex-wrap gap-2">
              <CopyButton value={address} label="Copy wallet address" />
              <CopyButton value={reference} label="Copy deposit reference" />
            </div>
          </div>
          {addressIsShared ? (
            <p className="mt-2 text-xs text-ink-muted">
              This receiving address may be shared across clients. Keep your deposit reference and upload a receipt so we can match your payment.
            </p>
          ) : null}
        </Step>

        <Step number="3" title="Send the payment from your wallet">
          <ul className="list-disc space-y-1 pl-4 text-ink-muted">
            <li>Send only {assetSymbol} on {networkName}.</li>
            <li>Do not send from an exchange withdrawal using a different network or token.</li>
            <li>Cryptocurrency transfers cannot be reversed once broadcast.</li>
            <li>Include enough network fee in your wallet so the transfer completes.</li>
          </ul>
        </Step>

        <Step number="4" title="Save proof of payment">
          <p>
            Take a screenshot or export the transaction receipt from your wallet. You will upload it in the next section.
            A receipt helps review. It does not credit your account by itself.
          </p>
        </Step>

        <Step number="5" title="Mark as paid on this page">
          <p>
            After the transfer is sent, upload your receipt below and click <strong className="font-medium text-ink">I have paid</strong>.
            An Aztek administrator will verify the payment and credit your account. Blockchain confirmation alone does not mean the deposit is credited.
          </p>
        </Step>
      </ol>
    </section>
  );
}

function Step({ number, title, children }: { number: string; title: string; children: React.ReactNode }) {
  return (
    <li className="rounded-lg border border-line p-4">
      <p className="text-xs font-medium text-brand">Step {number}</p>
      <h3 className="mt-1 text-sm font-medium text-ink">{title}</h3>
      <div className="mt-2 text-sm leading-6 text-ink">{children}</div>
    </li>
  );
}
