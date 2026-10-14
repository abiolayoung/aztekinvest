import { createHmac, timingSafeEqual } from "crypto";
import { NextResponse } from "next/server";
import { z } from "zod";
import { createAdminClient } from "@/lib/supabase/admin";

const payloadSchema = z.object({
  network_identifier: z.string().min(2),
  transaction_hash: z.string().min(32),
  output_index: z.number().int().nonnegative().optional(),
  asset_identifier: z.string().min(2),
  to_address: z.string().min(20),
  raw_amount: z.string().regex(/^\d+(\.\d{1,18})?$/).optional(),
  confirmation_count: z.number().int().nonnegative().optional(),
  provider_reference: z.string().max(200).optional(),
});

export async function POST(request: Request) {
  const secret = process.env.CRYPTO_PROVIDER_WEBHOOK_SECRET;
  if (!secret) {
    return NextResponse.json({ error: "Crypto provider is not configured." }, { status: 503 });
  }
  const body = await request.text();
  const signature = request.headers.get("x-aztek-signature") ?? "";
  const expected = createHmac("sha256", secret).update(body).digest("hex");
  const left = Buffer.from(signature);
  const right = Buffer.from(expected);
  if (left.length !== right.length || !timingSafeEqual(left, right)) {
    return NextResponse.json({ error: "Invalid signature." }, { status: 401 });
  }

  let json: unknown;
  try {
    json = JSON.parse(body);
  } catch {
    return NextResponse.json({ error: "Invalid payload." }, { status: 400 });
  }
  const parsed = payloadSchema.safeParse(json);
  if (!parsed.success) return NextResponse.json({ error: "Invalid payload." }, { status: 400 });

  const admin = createAdminClient();
  if (!admin) return NextResponse.json({ error: "Service role is not configured." }, { status: 503 });
  const { error } = await admin.rpc("record_provider_observation", {
    network_identifier: parsed.data.network_identifier,
    transaction_hash: parsed.data.transaction_hash,
    output_index: parsed.data.output_index ?? 0,
    asset_identifier: parsed.data.asset_identifier,
    to_address: parsed.data.to_address,
    raw_amount: parsed.data.raw_amount ?? null,
    confirmation_count: parsed.data.confirmation_count ?? 0,
    provider_reference: parsed.data.provider_reference ?? null,
  });
  if (error) return NextResponse.json({ error: "The observation could not be recorded." }, { status: 422 });
  return NextResponse.json({ ok: true, credited: false });
}
