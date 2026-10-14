/** Official payment QR assets shipped with configured receiving wallets. */
const officialQrByKey: Record<string, string> = {
  "BTC:bitcoin": "/wallets/btc-receive-qr.jpg",
  "BTC:btc": "/wallets/btc-receive-qr.jpg",
  "USDT:bnb-smart-chain": "/wallets/usdt-bep20-receive-qr.jpg",
  "USDT:bep20": "/wallets/usdt-bep20-receive-qr.jpg",
  "USDT:bsc": "/wallets/usdt-bep20-receive-qr.jpg",
};

export function officialWalletQrPath(symbol: string, networkIdentifier: string): string | null {
  const sym = symbol.trim().toUpperCase();
  const network = networkIdentifier.trim().toLowerCase();
  const direct = officialQrByKey[`${sym}:${network}`];
  if (direct) return direct;
  if (sym === "BTC" && (network.includes("bitcoin") || network === "btc")) {
    return "/wallets/btc-receive-qr.jpg";
  }
  if (sym === "USDT" && (network.includes("bnb") || network.includes("bsc") || network.includes("bep20"))) {
    return "/wallets/usdt-bep20-receive-qr.jpg";
  }
  return null;
}

export const BTC_RECEIVING_ADDRESS = "bc1qwfnufgkd4tuwzxngpx9h2rf6kglgjuqqgs0qze";
export const USDT_BEP20_RECEIVING_ADDRESS = "0x871309EA406CDbB36153E4D887fFc223b98cDc16";
