export type LedgerLeg = {
  debitCents: bigint;
  creditCents: bigint;
};

export function legsBalance(legs: LedgerLeg[]): boolean {
  if (legs.length < 2) return false;
  let debits = 0n;
  let credits = 0n;
  for (const leg of legs) {
    const oneSided =
      (leg.debitCents > 0n && leg.creditCents === 0n) ||
      (leg.creditCents > 0n && leg.debitCents === 0n);
    if (!oneSided) return false;
    debits += leg.debitCents;
    credits += leg.creditCents;
  }
  return debits === credits && debits > 0n;
}

export function accountValue(input: {
  cashCents: bigint;
  reservedCents: bigint;
  holdingsValueCents: bigint;
}): bigint {
  return input.cashCents + input.reservedCents + input.holdingsValueCents;
}

export function availableWithdrawalCents(cashCents: bigint): bigint {
  return cashCents > 0n ? cashCents : 0n;
}

export function allocateAtCost(input: {
  cashCents: bigint;
  holdingsValueCents: bigint;
  amountCents: bigint;
}): { cashCents: bigint; holdingsValueCents: bigint; totalCents: bigint } | null {
  if (input.amountCents <= 0n || input.amountCents > input.cashCents) return null;
  const cashCents = input.cashCents - input.amountCents;
  const holdingsValueCents = input.holdingsValueCents + input.amountCents;
  return {
    cashCents,
    holdingsValueCents,
    totalCents: cashCents + holdingsValueCents,
  };
}

export function depositCreditLegs(amountCents: bigint): LedgerLeg[] {
  return [
    { debitCents: amountCents, creditCents: 0n },
    { debitCents: 0n, creditCents: amountCents },
  ];
}

export function allocationLegs(amountCents: bigint): LedgerLeg[] {
  return [
    { debitCents: amountCents, creditCents: 0n },
    { debitCents: 0n, creditCents: amountCents },
    { debitCents: 0n, creditCents: amountCents },
    { debitCents: amountCents, creditCents: 0n },
  ];
}

export function unrealizedResult(
  costCents: bigint | null,
  marketCents: bigint | null,
): bigint | null {
  if (costCents === null || marketCents === null) return null;
  return marketCents - costCents;
}

export function isInvestmentGain(transactionType: string): boolean {
  return transactionType === "investment_close";
}

export function countsAsConfirmedCash(status: string): boolean {
  return status === "credited";
}
