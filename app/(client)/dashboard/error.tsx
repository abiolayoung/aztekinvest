"use client";

export default function DashboardError({ reset }: { error: Error; reset: () => void }) {
  return (
    <div role="alert" className="rounded-card border border-red-200 bg-white p-5">
      <h1 className="text-lg font-medium">Account records could not be loaded</h1>
      <p className="mt-2 text-sm text-ink-muted">Refresh the page. No balance is shown when the records cannot be read.</p>
      <button className="mt-4 rounded-lg bg-brand px-3 py-2 text-sm text-white" onClick={reset} type="button">
        Try again
      </button>
    </div>
  );
}
