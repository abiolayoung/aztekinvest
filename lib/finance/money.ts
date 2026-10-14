const USD_PATTERN = /^\d+(\.\d{1,2})?$/;

export function parseUsdToCents(input: string): bigint | null {
  const trimmed = input.trim().replace(/[$,\s]/g, "");
  if (!USD_PATTERN.test(trimmed)) return null;
  const [whole, fraction = ""] = trimmed.split(".");
  if (whole.length > 15) return null;
  return BigInt(whole) * 100n + BigInt(fraction.padEnd(2, "0"));
}

export function formatUsdCents(cents: bigint | number | string | null | undefined): string {
  const value = toCents(cents);
  const negative = value < 0n;
  const absolute = negative ? -value : value;
  const dollars = absolute / 100n;
  const remainder = (absolute % 100n).toString().padStart(2, "0");
  const grouped = dollars.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return `${negative ? "-" : ""}$${grouped}.${remainder}`;
}

export function toCents(value: bigint | number | string | null | undefined): bigint {
  if (typeof value === "bigint") return value;
  if (value === null || value === undefined || value === "") return 0n;
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value)) {
      throw new Error("Financial amount is outside the safe integer range.");
    }
    return BigInt(value);
  }
  if (!/^-?\d+$/.test(value)) {
    throw new Error("Financial amount is not an integer number of cents.");
  }
  return BigInt(value);
}
