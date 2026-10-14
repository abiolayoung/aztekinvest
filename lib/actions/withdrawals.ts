"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/session";
import { parseUsdToCents } from "@/lib/finance/money";
import { publicDbError } from "@/lib/security/errors";
import { destinationAddressSchema } from "@/lib/validation/schemas";

export async function requestWithdrawalAction(_state: { error?: string; message?: string }, formData: FormData) {
  const cents = parseUsdToCents(String(formData.get("amount") ?? ""));
  const address = destinationAddressSchema.safeParse(formData.get("destinationAddress"));
  const assetId = String(formData.get("assetId") ?? "");
  const acknowledged = formData.get("acknowledged") === "on";
  if (!cents) return { error: "Enter an amount in dollars and cents." };
  if (!address.success) return { error: address.error.issues[0]?.message ?? "Enter a receiving address." };
  if (!acknowledged) return { error: "Confirm the destination address and withdrawal terms before submitting." };

  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("request_withdrawal", {
    amount_cents: cents.toString(),
    asset_id: assetId,
    destination_address: address.data,
  });
  if (error) return { error: publicDbError(error, "The withdrawal request could not be submitted.") };
  revalidatePath("/dashboard/withdrawals");
  revalidatePath("/dashboard");
  return { message: "Your withdrawal request has been submitted for review." };
}

export async function cancelWithdrawalAction(formData: FormData) {
  const withdrawalId = String(formData.get("withdrawalId") ?? "");
  const { supabase } = await requireUser();
  await supabase.rpc("cancel_withdrawal", { withdrawal_id: withdrawalId });
  revalidatePath("/dashboard/withdrawals");
  redirect("/dashboard/withdrawals");
}
