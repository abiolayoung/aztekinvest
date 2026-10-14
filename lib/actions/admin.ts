"use server";

import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/auth/session";
import { can } from "@/lib/auth/permissions";
import { parseUsdToCents } from "@/lib/finance/money";
import { publicDbError } from "@/lib/security/errors";
import { destinationAddressError } from "@/lib/security/sensitive";
import { processNotificationOutbox } from "@/lib/notifications/dispatch";
import { depositReviewSchema } from "@/lib/validation/schemas";

export type ActionState = { error?: string; message?: string };

function denied(): ActionState {
  return { error: "You do not have permission to do that." };
}

export async function reviewDepositAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "reviewDeposits")) return denied();
  const parsed = depositReviewSchema.safeParse({
    decision: formData.get("decision"),
    reason: formData.get("reason"),
    creditAmount: formData.get("creditAmount") || undefined,
    observedCryptoAmount: formData.get("observedCryptoAmount") || undefined,
    confirmationCount: formData.get("confirmationCount") || undefined,
    observedAddress: formData.get("observedAddress") || undefined,
    confirmed: formData.get("confirmed") === "on",
  });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Check the review and try again." };
  const cents = parsed.data.creditAmount ? parseUsdToCents(parsed.data.creditAmount) : null;
  const { error } = await supabase.rpc("review_deposit", {
    deposit_id: String(formData.get("depositId")),
    decision: parsed.data.decision,
    reason: parsed.data.reason,
    credit_amount_cents: cents ? cents.toString() : null,
    observed_crypto_amount: parsed.data.observedCryptoAmount || null,
    confirmation_count: parsed.data.confirmationCount ? Number(parsed.data.confirmationCount) : null,
    observed_address: parsed.data.observedAddress || null,
  });
  if (error) return { error: publicDbError(error, "The deposit decision could not be saved.") };
  const depositId = String(formData.get("depositId") ?? "");
  await processNotificationOutbox();
  revalidatePath("/admin/deposits");
  revalidatePath(`/admin/deposits/${depositId}`);
  revalidatePath("/dashboard");
  revalidatePath("/dashboard/deposits");
  revalidatePath(`/dashboard/deposits/${depositId}`);
  revalidatePath("/dashboard/transactions");
  return {
    message:
      parsed.data.decision === "approve"
        ? "Marked Received. Client dashboard cash is updated."
        : parsed.data.decision === "reject"
          ? "Payment rejected."
          : "Kept under review.",
  };
}

export async function reviewWithdrawalAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "reviewWithdrawals")) return denied();
  const reason = String(formData.get("reason") ?? "").trim();
  if (reason.length < 8) return { error: "Enter a reason of at least 8 characters." };
  const { error } = await supabase.rpc("review_withdrawal", {
    withdrawal_id: String(formData.get("withdrawalId")),
    decision: String(formData.get("decision")),
    reason,
    payout_transaction_hash: String(formData.get("payoutHash") ?? "") || null,
  });
  if (error) return { error: publicDbError(error, "The withdrawal decision could not be saved.") };
  revalidatePath("/admin/withdrawals");
  revalidatePath("/dashboard/withdrawals");
  return { message: "Withdrawal decision saved." };
}

export async function verificationAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "reviewVerification")) return denied();
  const { error } = await supabase.rpc("admin_set_verification", {
    target_user: String(formData.get("userId")),
    next_status: String(formData.get("status")),
    reason: String(formData.get("reason") ?? ""),
  });
  if (error) return { error: publicDbError(error, "The verification decision could not be saved.") };
  await processNotificationOutbox();
  revalidatePath("/admin/clients");
  return { message: "Verification updated." };
}

export async function accountStatusAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "manageClients")) return denied();
  const { error } = await supabase.rpc("admin_set_account_status", {
    target_user: String(formData.get("userId")),
    next_status: String(formData.get("status")),
    reason: String(formData.get("reason") ?? ""),
  });
  if (error) return { error: publicDbError(error, "The account status could not be changed.") };
  revalidatePath("/admin/clients");
  return { message: "Account status updated." };
}

export async function allocateAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "manageInvestments")) return denied();
  const cents = parseUsdToCents(String(formData.get("amount") ?? ""));
  if (!cents) return { error: "Enter an allocation amount in dollars and cents." };
  const { error } = await supabase.rpc("record_investment_allocation", {
    target_user: String(formData.get("userId")),
    category: String(formData.get("category")),
    description: String(formData.get("description") ?? ""),
    amount_cents: cents.toString(),
    execution_reference: String(formData.get("executionReference") ?? ""),
    evidence_reference: String(formData.get("evidenceReference") ?? ""),
    executed_at: String(formData.get("executedAt") ?? "") || null,
  });
  if (error) return { error: publicDbError(error, "The allocation could not be recorded.") };
  revalidatePath("/admin/portfolios");
  revalidatePath("/dashboard");
  return { message: "Allocation recorded at cost. It does not create a gain." };
}

export async function valuationAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "manageInvestments")) return denied();
  const cents = parseUsdToCents(String(formData.get("valuation") ?? ""));
  if (cents === null) return { error: "Enter the verified valuation in dollars and cents." };
  const { error } = await supabase.rpc("record_holding_valuation", {
    holding_id: String(formData.get("holdingId")),
    current_valuation_cents: cents.toString(),
    evidence_reference: String(formData.get("evidenceReference") ?? ""),
  });
  if (error) return { error: publicDbError(error, "The valuation could not be recorded.") };
  revalidatePath("/admin/portfolios");
  revalidatePath("/dashboard/portfolio");
  return { message: "Verified valuation recorded." };
}

export async function closeHoldingAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "manageInvestments")) return denied();
  const cents = parseUsdToCents(String(formData.get("proceeds") ?? ""));
  if (cents === null) return { error: "Enter proceeds in dollars and cents. Use 0.00 if there were none." };
  const { error } = await supabase.rpc("close_investment_holding", {
    holding_id: String(formData.get("holdingId")),
    proceeds_cents: cents.toString(),
    execution_reference: String(formData.get("executionReference") ?? ""),
    evidence_reference: String(formData.get("evidenceReference") ?? ""),
  });
  if (error) return { error: publicDbError(error, "The holding could not be closed.") };
  revalidatePath("/admin/portfolios");
  return { message: "Holding closed and proceeds recorded." };
}

export async function feeAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "manageInvestments")) return denied();
  const cents = parseUsdToCents(String(formData.get("amount") ?? ""));
  if (!cents) return { error: "Enter a fee amount." };
  const { error } = await supabase.rpc("record_client_fee", {
    target_user: String(formData.get("userId")),
    amount_cents: cents.toString(),
    description: String(formData.get("description") ?? ""),
    evidence_reference: String(formData.get("evidenceReference") ?? ""),
  });
  if (error) return { error: publicDbError(error, "The fee could not be recorded.") };
  revalidatePath("/admin/portfolios");
  return { message: "Fee recorded against confirmed cash." };
}

export async function adjustmentAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "postAdjustments")) return denied();
  const cents = parseUsdToCents(String(formData.get("amount") ?? ""));
  if (!cents) return { error: "Enter an adjustment amount." };
  const { error } = await supabase.rpc("adjust_client_cash", {
    target_user: String(formData.get("userId")),
    direction: String(formData.get("direction")),
    amount_cents: cents.toString(),
    description: String(formData.get("description") ?? ""),
    reason: String(formData.get("reason") ?? ""),
    evidence_reference: String(formData.get("evidenceReference") ?? ""),
  });
  if (error) return { error: publicDbError(error, "The adjustment could not be posted.") };
  revalidatePath("/admin/clients");
  return { message: "Compensating cash entry posted. The original history was not overwritten." };
}

export async function saveAssetAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "manageWallets")) return denied();
  const address = String(formData.get("receivingAddress") ?? "").trim();
  if (address) {
    const addressError = destinationAddressError(address);
    if (addressError) return { error: addressError };
  }
  const minimum = parseUsdToCents(String(formData.get("minimum") ?? ""));
  const maximum = parseUsdToCents(String(formData.get("maximum") ?? ""));
  const feeRaw = String(formData.get("withdrawalFee") ?? "").trim();
  const fee = feeRaw ? parseUsdToCents(feeRaw) : null;
  if (String(formData.get("depositEnabled")) === "on" && (!minimum || !maximum)) {
    return { error: "Set a minimum and maximum before enabling deposits." };
  }
  const { error } = await supabase.rpc("upsert_deposit_asset", {
    asset_id: String(formData.get("assetId") ?? "") || null,
    symbol: String(formData.get("symbol") ?? ""),
    asset_name: String(formData.get("assetName") ?? ""),
    network_name: String(formData.get("networkName") ?? ""),
    network_identifier: String(formData.get("networkIdentifier") ?? ""),
    asset_contract: String(formData.get("assetContract") ?? ""),
    receiving_address: address,
    address_is_shared: formData.get("addressIsShared") === "on",
    address_verified: formData.get("addressVerified") === "on",
    minimum_deposit_cents: minimum ? minimum.toString() : "0",
    maximum_deposit_cents: maximum ? maximum.toString() : null,
    required_confirmations: Number(formData.get("requiredConfirmations") ?? 12),
    deposit_enabled: formData.get("depositEnabled") === "on",
    withdrawal_enabled: formData.get("withdrawalEnabled") === "on",
    withdrawal_fee_cents: fee ? fee.toString() : null,
    custody_provider: String(formData.get("custodyProvider") ?? ""),
    decimals: Number(formData.get("decimals") ?? 6),
  });
  if (error) return { error: publicDbError(error, "The asset configuration could not be saved.") };
  revalidatePath("/admin/wallets");
  revalidatePath("/dashboard/deposit");
  return { message: "Wallet configuration saved. No address was generated by the application." };
}

export async function settingsAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "manageSettings")) return denied();
  const { error } = await supabase.rpc("update_app_settings", {
    deposits_enabled: formData.get("depositsEnabled") === "on",
    withdrawals_enabled: formData.get("withdrawalsEnabled") === "on",
    support_email: String(formData.get("supportEmail") ?? ""),
    deposit_notification_email: String(formData.get("depositNotificationEmail") ?? ""),
    withdrawal_processing_notice: String(formData.get("withdrawalNotice") ?? ""),
    deposit_expiry_hours: Number(formData.get("depositExpiryHours") ?? 168),
  });
  if (error) return { error: publicDbError(error, "Settings could not be saved.") };
  revalidatePath("/admin/settings");
  revalidatePath("/dashboard/deposit");
  return { message: "Settings saved." };
}

export async function noticeAction(_state: ActionState, formData: FormData): Promise<ActionState> {
  const { supabase, profile } = await requireUser();
  if (!can(profile.role, "sendNotices")) return denied();
  const { error } = await supabase.rpc("send_account_notice", {
    target_user: String(formData.get("userId")),
    title: String(formData.get("title") ?? ""),
    message: String(formData.get("message") ?? ""),
  });
  if (error) return { error: publicDbError(error, "The notice could not be sent.") };
  revalidatePath("/admin/notifications");
  return { message: "Notice sent." };
}
