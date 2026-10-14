export default function Loading() {
  return (
    <div className="grid gap-4 md:grid-cols-4" aria-hidden="true">
      {Array.from({ length: 4 }).map((_, index) => (
        <div key={index} className="h-28 animate-pulse rounded-card bg-white" />
      ))}
    </div>
  );
}
