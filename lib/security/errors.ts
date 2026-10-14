export function publicDbError(error: { message?: string } | null, fallback: string): string {
  const message = error?.message?.trim() ?? "";
  if (!message) return fallback;
  if (/duplicate key|unique constraint/i.test(message)) {
    return "This conflicts with an existing record. If you already submitted this transaction hash, open the existing deposit.";
  }
  if (/permission denied|row-level security|jwt|not authorized/i.test(message)) {
    return "You do not have permission to do that.";
  }
  if (/^Too many requests/.test(message) || (/^[A-Z]/.test(message) && message.endsWith(".") && !/relation |syntax error|function /i.test(message))) {
    return message.replace(/^ERROR:\s*/i, "");
  }
  return fallback;
}
