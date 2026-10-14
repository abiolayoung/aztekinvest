import { Wordmark } from "@/components/brand/wordmark";

export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <main className="min-h-screen bg-canvas px-5 py-12">
      <div className="mx-auto w-full max-w-form">
        <Wordmark />
        <div className="mt-8 rounded-card border border-line bg-white p-6 shadow-card">{children}</div>
      </div>
    </main>
  );
}
