import { Wordmark } from "@/components/brand/wordmark";

export default function SetupPage() {
  return (
    <main className="mx-auto min-h-screen max-w-xl px-5 py-16">
      <Wordmark />
      <h1 className="mt-8 text-2xl font-medium">Supabase is not configured</h1>
      <p className="mt-3 text-sm leading-6 text-ink-muted">
        Copy <code>.env.example</code> to <code>.env.local</code> and add the project URL and anon key. Then run the SQL migrations in <code>supabase/migrations</code>. The service role key stays on the server and is required only for blockchain webhooks and email dispatch.
      </p>
    </main>
  );
}
