import { SiteFooter } from "@/components/layout/site-footer";
import { SiteHeader } from "@/components/layout/site-header";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { createClient } from "@/lib/supabase/server";

export default async function MarketingLayout({ children }: { children: React.ReactNode }) {
  let supportEmail = process.env.NEXT_PUBLIC_SUPPORT_EMAIL || null;
  if (isSupabaseConfigured()) {
    try {
      const supabase = await createClient();
      const { data } = await supabase.rpc("get_public_settings");
      const row = Array.isArray(data) ? data[0] : data;
      supportEmail = row?.support_email || supportEmail;
    } catch {
      supportEmail = supportEmail;
    }
  }

  return (
    <div className="flex min-h-screen flex-col bg-canvas">
      <SiteHeader />
      <div className="flex-1">{children}</div>
      <SiteFooter supportEmail={supportEmail} />
    </div>
  );
}
