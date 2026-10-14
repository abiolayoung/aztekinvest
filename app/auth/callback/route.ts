import { NextResponse } from "next/server";
import { appUrl, isSupabaseConfigured } from "@/lib/supabase/config";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const next = url.searchParams.get("next") || "/dashboard";
  const safeNext = next.startsWith("/") && !next.startsWith("//") ? next : "/dashboard";
  if (!isSupabaseConfigured()) {
    return NextResponse.redirect(new URL("/setup", appUrl()));
  }
  const code = url.searchParams.get("code");
  if (code) {
    const supabase = await createClient();
    await supabase.auth.exchangeCodeForSession(code);
  }
  return NextResponse.redirect(new URL(safeNext, appUrl()));
}
