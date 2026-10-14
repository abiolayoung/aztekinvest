export type PerformancePoint = {
  at: string;
  totalCents: bigint;
  source: string;
};

export type ExternalFlow = {
  at: string;
  cents: bigint;
};

export type PerformanceStatus = "not_yet_available" | "insufficient_history" | "ready";

const VERIFIED_SOURCES = new Set(["verified_valuation", "closing"]);

export function performanceStatus(points: PerformancePoint[]): PerformanceStatus {
  if (!points.some((point) => VERIFIED_SOURCES.has(point.source))) {
    return "not_yet_available";
  }
  if (points.length < 2) return "insufficient_history";
  return "ready";
}

export function modifiedDietzPpm(input: {
  start: { at: string; totalCents: bigint };
  end: { at: string; totalCents: bigint };
  flows: ExternalFlow[];
}): bigint | null {
  const startMs = Date.parse(input.start.at);
  const endMs = Date.parse(input.end.at);
  if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs <= startMs) {
    return null;
  }

  const totalMs = BigInt(Math.round(endMs - startMs));
  let flowSum = 0n;
  let weighted = input.start.totalCents * totalMs;

  for (const flow of input.flows) {
    const flowMs = Date.parse(flow.at);
    if (!Number.isFinite(flowMs) || flowMs <= startMs || flowMs > endMs) continue;
    const remaining = BigInt(Math.round(endMs - flowMs));
    weighted += flow.cents * remaining;
    flowSum += flow.cents;
  }

  if (weighted === 0n) return null;
  const gain = input.end.totalCents - input.start.totalCents - flowSum;
  return (gain * totalMs * 1_000_000n) / weighted;
}

export function formatReturnPpm(ppm: bigint): string {
  const negative = ppm < 0n;
  const absolute = negative ? -ppm : ppm;
  const hundredths = absolute / 100n;
  const units = hundredths / 100n;
  const fraction = (hundredths % 100n).toString().padStart(2, "0");
  return `${negative ? "-" : ""}${units.toString()}.${fraction}%`;
}

export type PerformancePeriod = "1M" | "3M" | "6M" | "1Y";

const PERIOD_DAYS: Record<PerformancePeriod, number> = {
  "1M": 30,
  "3M": 91,
  "6M": 182,
  "1Y": 365,
};

export function filterPoints(
  points: PerformancePoint[],
  period: PerformancePeriod,
  now = new Date(),
): PerformancePoint[] {
  const cutoff = now.getTime() - PERIOD_DAYS[period] * 86_400_000;
  return points
    .filter((point) => Date.parse(point.at) >= cutoff)
    .sort((a, b) => Date.parse(a.at) - Date.parse(b.at));
}

export function periodReturnPpm(
  points: PerformancePoint[],
  flows: ExternalFlow[],
  period: PerformancePeriod,
  now = new Date(),
): { status: PerformanceStatus; ppm: bigint | null; start?: string; end?: string } {
  const window = filterPoints(points, period, now);
  const status = performanceStatus(window);
  if (status !== "ready") return { status, ppm: null };
  const start = window[0];
  const end = window[window.length - 1];
  const ppm = modifiedDietzPpm({ start, end, flows });
  if (ppm === null) return { status: "insufficient_history", ppm: null };
  return { status: "ready", ppm, start: start.at, end: end.at };
}
