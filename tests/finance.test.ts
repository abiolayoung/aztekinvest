import { describe, expect, it } from "vitest";
import { accountValue, allocateAtCost, allocationLegs, availableWithdrawalCents, countsAsConfirmedCash, depositCreditLegs, legsBalance, unrealizedResult } from "@/lib/finance/accounting";
import { formatUsdCents, parseUsdToCents } from "@/lib/finance/money";
import { formatReturnPpm, modifiedDietzPpm, performanceStatus, periodReturnPpm } from "@/lib/finance/performance";

describe("money", () => {
  it("parses dollars and cents without floating-point authority", () => {
    expect(parseUsdToCents("1,250.50")).toBe(125050n);
    expect(parseUsdToCents("$10")).toBe(1000n);
    expect(parseUsdToCents("10.5")).toBe(1050n);
    expect(parseUsdToCents("10.555")).toBeNull();
    expect(parseUsdToCents("-5")).toBeNull();
  });

  it("formats cents with grouping", () => {
    expect(formatUsdCents(125050n)).toBe("$1,250.50");
    expect(formatUsdCents(-5n)).toBe("-$0.05");
  });
});

describe("ledger rules", () => {
  it("balances a deposit credit and does not treat the request as cash", () => {
    expect(legsBalance(depositCreditLegs(100000n))).toBe(true);
    expect(countsAsConfirmedCash("awaiting_payment")).toBe(false);
    expect(countsAsConfirmedCash("credited")).toBe(true);
  });

  it("moves cash into a holding without creating profit", () => {
    expect(legsBalance(allocationLegs(40000n))).toBe(true);
    const next = allocateAtCost({ cashCents: 100000n, holdingsValueCents: 0n, amountCents: 40000n });
    expect(next).toEqual({ cashCents: 60000n, holdingsValueCents: 40000n, totalCents: 100000n });
  });

  it("keeps reserved withdrawals out of available cash but inside account value", () => {
    expect(availableWithdrawalCents(60000n)).toBe(60000n);
    expect(accountValue({ cashCents: 60000n, reservedCents: 20000n, holdingsValueCents: 40000n })).toBe(120000n);
  });

  it("does not invent unrealized profit without a market value", () => {
    expect(unrealizedResult(40000n, null)).toBeNull();
    expect(unrealizedResult(40000n, 45000n)).toBe(5000n);
  });

  it("rejects unbalanced or empty entries", () => {
    expect(legsBalance([{ debitCents: 10n, creditCents: 0n }])).toBe(false);
    expect(legsBalance([{ debitCents: 10n, creditCents: 10n }])).toBe(false);
  });
});

describe("performance", () => {
  it("returns 10 percent when value rises and there are no external flows", () => {
    const ppm = modifiedDietzPpm({
      start: { at: "2026-01-01T00:00:00.000Z", totalCents: 100000n },
      end: { at: "2026-04-01T00:00:00.000Z", totalCents: 110000n },
      flows: [],
    });
    expect(ppm).toBe(100000n);
    expect(formatReturnPpm(ppm!)).toBe("10.00%");
  });

  it("does not count a deposit as investment profit", () => {
    const ppm = modifiedDietzPpm({
      start: { at: "2026-01-01T00:00:00.000Z", totalCents: 100000n },
      end: { at: "2026-02-01T00:00:00.000Z", totalCents: 150000n },
      flows: [{ at: "2026-01-15T00:00:00.000Z", cents: 50000n }],
    });
    expect(ppm).toBe(0n);
  });

  it("withholds a return until verified history exists", () => {
    expect(performanceStatus([{ at: "2026-01-01T00:00:00.000Z", totalCents: 100n, source: "allocation_at_cost" }])).toBe("not_yet_available");
    const result = periodReturnPpm(
      [
        { at: "2026-01-01T00:00:00.000Z", totalCents: 100000n, source: "allocation_at_cost" },
        { at: "2026-03-01T00:00:00.000Z", totalCents: 110000n, source: "verified_valuation" },
      ],
      [],
      "1Y",
      new Date("2026-04-01T00:00:00.000Z"),
    );
    expect(result.status).toBe("ready");
    expect(result.ppm).toBe(100000n);
  });
});
