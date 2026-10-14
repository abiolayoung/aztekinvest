import { NextResponse } from "next/server";
import { processNotificationOutbox } from "@/lib/notifications/dispatch";

export async function POST(request: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "Unauthorized." }, { status: 401 });
  }
  const result = await processNotificationOutbox(50);
  return NextResponse.json(result);
}
