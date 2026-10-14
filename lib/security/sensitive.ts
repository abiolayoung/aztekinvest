const SECRET_LANGUAGE = /(seed phrase|mnemonic|private key|secret key)/i;

export function looksLikeSecretPhrase(value: string): boolean {
  if (SECRET_LANGUAGE.test(value)) return true;
  const words = value.trim().split(/\s+/);
  return words.length >= 12 && words.every((word) => /^[a-z]+$/i.test(word));
}

export function destinationAddressError(value: string): string | null {
  const cleaned = value.trim();
  if (!cleaned || looksLikeSecretPhrase(cleaned) || /\s/.test(cleaned)) {
    return "Enter a receiving address. Never send a seed phrase or private key.";
  }
  if (!/^[A-Za-z0-9]{20,128}$/.test(cleaned)) {
    return "The receiving address does not look valid.";
  }
  if (/^[0-9a-fA-F]{64}$/.test(cleaned) || /^0x[0-9a-fA-F]{64}$/.test(cleaned)) {
    return "That value looks like a private key. Enter only the receiving address.";
  }
  return null;
}

export function transactionHashError(value: string): string | null {
  const cleaned = value.trim();
  if (!cleaned || looksLikeSecretPhrase(cleaned) || /\s/.test(cleaned)) {
    return "Enter the transaction hash. Never send a seed phrase or private key.";
  }
  if (!/^[A-Za-z0-9]{32,128}$/.test(cleaned)) {
    return "Enter the transaction hash from your wallet receipt.";
  }
  return null;
}
