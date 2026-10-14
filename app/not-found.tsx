import Link from "next/link";

export default function NotFound() {
  return (
    <main className="mx-auto max-w-lg px-5 py-24">
      <h1 className="text-2xl font-medium">Page not found</h1>
      <p className="mt-2 text-sm text-ink-muted">That page is not part of the Aztek portal.</p>
      <Link href="/" className="mt-6 inline-flex text-sm text-brand">Return home</Link>
    </main>
  );
}
