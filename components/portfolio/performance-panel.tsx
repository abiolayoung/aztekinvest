"use client";

import { useState } from "react";
import { CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { formatUsdCents } from "@/lib/finance/money";
import {
  filterPoints,
  formatReturnPpm,
  periodReturnPpm,
  type ExternalFlow,
  type PerformancePeriod,
  type PerformancePoint,
} from "@/lib/finance/performance";

const periods: PerformancePeriod[] = ["1M", "3M", "6M", "1Y"];

function chartDollars(cents: bigint): number | null {
  const limit = BigInt(Number.MAX_SAFE_INTEGER);
  if (cents > limit || cents < -limit) return null;
  return Number(cents) / 100;
}

export function PerformancePanel({
  points,
  flows,
}: {
  points: PerformancePoint[];
  flows: ExternalFlow[];
}) {
  const [period, setPeriod] = useState<PerformancePeriod>("1Y");
  const result = periodReturnPpm(points, flows, period);
  const windowPoints = filterPoints(points, period);
  const chart = windowPoints.map((point) => {
    const value = chartDollars(point.totalCents);
    return value === null ? null : { date: point.at.slice(0, 10), value };
  });
  const canChart = result.status === "ready" && chart.length >= 2 && chart.every((point) => point !== null);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-sm text-ink-muted">Portfolio performance</p>
          <p className="numeric mt-1 text-2xl font-medium">
            {result.status === "ready" && result.ppm !== null ? formatReturnPpm(result.ppm) : "Not yet available"}
          </p>
          <p className="mt-1 max-w-xl text-xs leading-5 text-ink-muted">
            {result.status === "ready"
              ? "Money-weighted return between recorded valuations. Deposits and withdrawals are treated as cash flows, not as investment gains."
              : result.status === "insufficient_history"
                ? "Insufficient history for this period."
                : "A percentage return is shown only after verified valuation history exists."}
          </p>
        </div>
        <div className="flex gap-1" role="group" aria-label="Performance period">
          {periods.map((item) => (
            <button
              key={item}
              type="button"
              onClick={() => setPeriod(item)}
              className={`rounded-lg px-2.5 py-1 text-xs ${period === item ? "bg-brand text-white" : "bg-muted text-ink"}`}
            >
              {item}
            </button>
          ))}
        </div>
      </div>
      {canChart ? (
        <div className="h-56">
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={chart as { date: string; value: number }[]}>
              <CartesianGrid stroke="#E2E7E2" vertical={false} />
              <XAxis dataKey="date" tick={{ fontSize: 12, fill: "#6B756E" }} />
              <YAxis
                tick={{ fontSize: 12, fill: "#6B756E" }}
                tickFormatter={(value) => formatUsdCents(BigInt(Math.round(Number(value) * 100)))}
                width={88}
              />
              <Tooltip formatter={(value) => formatUsdCents(BigInt(Math.round(Number(value) * 100)))} />
              <Line type="monotone" dataKey="value" stroke="#123C32" strokeWidth={2} dot={false} />
            </LineChart>
          </ResponsiveContainer>
        </div>
      ) : (
        <p className="rounded-lg bg-muted px-3 py-6 text-sm text-ink-muted">
          Your portfolio valuation will appear here when verified investment records become available.
        </p>
      )}
    </div>
  );
}
