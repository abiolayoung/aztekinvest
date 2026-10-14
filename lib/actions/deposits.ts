"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/session";
import { parseUsdToCents } from "@/lib/finance/money";
import { processNotificationOutbox } from "@/lib/notifications/dispatch";
import { publicDbError } from "@/lib/security/errors";
import { transactionHashError } from "@/lib/security/sensitive";

const receiptTypes = new Set(["image/jpeg", "image/png", "image/webp", "application/pdf"]);

export async function createDepositAction(input: {
  amount: string;
  assetId: string;
  idempotencyKey: string;
  riskAcknowledged: boolean;
}): Promise<{ ok: true; id: string } | { ok: false; error: string }> {
  const cents = parseUsdToCents(input.amount);
  if (!cents) return { ok: false, error: "Enter an amount in dollars and cents." };
  if (!/^[0-9a-f-]{36}$/i.test(input.idempotencyKey)) {
    return { ok: false, error: "The deposit form expired. Refresh and try again." };
  }
  const { supabase } = await requireUser();
  const { data, error } = await supabase.rpc("create_deposit_request", {
    amount_cents: cents.toString(),
    asset_id: input.assetId,
    idempotency_key: input.idempotencyKey,
    risk_acknowledged: input.riskAcknowledged,
  });
  if (error) return { ok: false, error: publicDbError(error, "The deposit request could not be created.") };
  await processNotificationOutbox();
  revalidatePath("/dashboard");
  revalidatePath("/dashboard/deposits");
  revalidatePath("/admin/deposits");
  return { ok: true, id: String(data) };
}

export async function markDepositPaidAction(_state: { error?: string; message?: string }, formData: FormData) {
  const depositId = String(formData.get("depositId") ?? "");
  const hashValue = String(formData.get("transactionHash") ?? "").trim();
  const receipt = formData.get("receipt");
  if (!(receipt instanceof File) || receipt.size === 0) {
    return { error: "Upload a payment receipt image or PDF." };
  }
  if (receipt.size > 5 * 1024 * 1024) return { error: "Keep the receipt under 5 MB." };
  if (!receiptTypes.has(receipt.type)) return { error: "Upload a JPEG, PNG, WebP, or PDF receipt." };
  if (hashValue) {
    const hashError = transactionHashError(hashValue);
    if (hashError) return { error: hashError };
  }

  const { supabase, user } = await requireUser();
  const safeName = receipt.name.replace(/[^A-Za-z0-9._-]/g, "_").slice(0, 120) || "receipt";
  const objectPath = `${user.id}/${depositId}/${Date.now()}-${safeName}`;
  const { error: uploadError } = await supabase.storage.from("deposit-receipts").upload(objectPath, receipt, {
    contentType: receipt.type,
    upsert: false,
  });
  if (uploadError) return { error: "The receipt could not be uploaded. Try again." };

  const { error } = await supabase.rpc("mark_deposit_paid", {
    deposit_id: depositId,
    receipt_path: objectPath,
    receipt_file_name: safeName,
    receipt_content_type: receipt.type,
    transaction_hash: hashValue || null,
  });
  if (error) {
    await supabase.storage.from("deposit-receipts").remove([objectPath]);
    return { error: publicDbError(error, "The payment declaration could not be saved.") };
  }
  await processNotificationOutbox();
  revalidatePath(`/dashboard/deposits/${depositId}`);
  revalidatePath("/dashboard/deposits");
  revalidatePath("/admin/deposits");
  return { message: "Payment submitted for review. Your account is not credited until an administrator verifies the receipt." };
}

export async function cancelDepositAction(formData: FormData) {
  const depositId = String(formData.get("depositId") ?? "");
  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("cancel_deposit_request", { deposit_id: depositId });
  if (error) return;
  revalidatePath("/dashboard/deposits");
  redirect("/dashboard/deposits");
}
