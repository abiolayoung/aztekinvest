export function isSupabaseConfigured(): boolean {
  return Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);
}

export function supabaseUrl(): string {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!url) throw new Error("Supabase URL is not configured.");
  return url;
}

export function supabaseAnonKey(): string {
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!key) throw new Error("Supabase anon key is not configured.");
  return key;
}

export function appUrl(): string {
  return process.env.APP_URL || process.env.NEXT_PUBLIC_APP_URL || "http://localhost:3000";
}
