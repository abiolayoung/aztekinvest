import { NextResponse } from "next/server";
import { requireUser } from "@/lib/auth/session";
import { labelFor, ledgerTypeLabel } from "@/lib/format/labels";

export async function GET() {
  const { supabase, user } = await requireUser();
  const { data, error } = await supabase
    .from("ledger_transactions")
    .select("reference, transaction_type, description, created_at")
    .order("created_at", { ascending: false })
    .limit(1000);
  if (error) {
    return NextResponse.json({ error: "The statement could not be prepared." }, { status: 500 });
  }
  const lines = ["created_at,reference,type,description"];
  for (const row of data ?? []) {
    lines.push(
      [row.created_at, row.reference, labelFor(ledgerTypeLabel, row.transaction_type), row.description]
        .map((value) => `"${String(value ?? "").replaceAll('"', '""')}"`)
        .join(","),
    );
  }
  return new NextResponse(lines.join("\n"), {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="aztek-statement-${user.id}.csv"`,
    },
  });
}
