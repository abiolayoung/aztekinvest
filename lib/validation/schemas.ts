import { z } from "zod";
import { parseUsdToCents } from "@/lib/finance/money";
import { destinationAddressError, transactionHashError } from "@/lib/security/sensitive";
import { planIds } from "@/lib/plans";

export const passwordSchema = z
  .string()
  .min(12, "Use at least 12 characters.")
  .regex(/[a-z]/, "Include a lowercase letter.")
  .regex(/[A-Z]/, "Include an uppercase letter.")
  .regex(/[0-9]/, "Include a number.")
  .regex(/[^A-Za-z0-9]/, "Include a symbol.");

export const registerSchema = z
  .object({
    fullName: z.string().trim().min(2, "Enter your full legal name.").max(120),
    email: z.string().trim().email("Enter a valid email address."),
    password: passwordSchema,
    confirmPassword: z.string(),
    countryCode: z.string().regex(/^[A-Z]{2}$/, "Choose your country of residence."),
    planId: z.enum(planIds, { errorMap: () => ({ message: "Choose an investment plan to continue." }) }),
    acceptTerms: z.literal(true, {
      errorMap: () => ({ message: "Accept the terms and privacy notice to continue." }),
    }),
  })
  .refine((value) => value.password === value.confirmPassword, {
    path: ["confirmPassword"],
    message: "Passwords do not match.",
  });

export const loginSchema = z.object({
  email: z.string().trim().email("Enter a valid email address."),
  password: z.string().min(1, "Enter your password."),
});

export const forgotPasswordSchema = z.object({
  email: z.string().trim().email("Enter a valid email address."),
});

export const resetPasswordSchema = z
  .object({
    password: passwordSchema,
    confirmPassword: z.string(),
  })
  .refine((value) => value.password === value.confirmPassword, {
    path: ["confirmPassword"],
    message: "Passwords do not match.",
  });

export const usdAmountSchema = z.string().trim().refine((value) => {
  const cents = parseUsdToCents(value);
  return cents !== null && cents > 0n;
}, "Enter an amount in dollars and cents.");

export const profileSchema = z.object({
  fullName: z.string().trim().min(2, "Enter your full legal name.").max(120),
  countryCode: z.string().regex(/^[A-Z]{2}$/, "Choose your country of residence."),
  phone: z
    .string()
    .trim()
    .refine((value) => value === "" || /^\+?[0-9 ()-]{7,32}$/.test(value), "Enter a valid phone number or leave it blank."),
  emailNotifications: z.boolean(),
});

export const contactSchema = z.object({
  fullName: z.string().trim().min(2, "Enter your name.").max(120),
  email: z.string().trim().email("Enter a valid email address."),
  message: z.string().trim().min(10, "Enter a message of at least 10 characters.").max(4000),
  companyWebsite: z.string().max(0).optional().or(z.literal("")),
});

export const supportSchema = z.object({
  subject: z.string().trim().min(3, "Enter a subject.").max(160),
  message: z.string().trim().min(1, "Enter a message.").max(4000),
});

export const transactionHashSchema = z.string().trim().superRefine((value, context) => {
  const error = transactionHashError(value);
  if (error) context.addIssue({ code: "custom", message: error });
});

export const destinationAddressSchema = z.string().trim().superRefine((value, context) => {
  const error = destinationAddressError(value);
  if (error) context.addIssue({ code: "custom", message: error });
});

export const depositReviewSchema = z.object({
  decision: z.enum(["approve", "reject", "flag"]),
  reason: z.string().trim().min(8, "Enter a reason of at least 8 characters.").max(2000),
  creditAmount: z.string().trim().optional(),
  observedCryptoAmount: z.string().trim().optional(),
  confirmationCount: z.string().trim().optional(),
  observedAddress: z.string().trim().optional(),
  confirmed: z.boolean().optional(),
}).superRefine((value, context) => {
  if (value.decision !== "approve") return;
  if (!value.confirmed) {
    context.addIssue({ code: "custom", path: ["confirmed"], message: "Confirm that this credit should be posted once." });
  }
  const cents = value.creditAmount ? parseUsdToCents(value.creditAmount) : null;
  if (!cents || cents <= 0n) {
    context.addIssue({ code: "custom", path: ["creditAmount"], message: "Enter the USD amount verified for credit." });
  }
  if (value.observedCryptoAmount) {
    if (!/^\d+(\.\d{1,18})?$/.test(value.observedCryptoAmount) || Number(value.observedCryptoAmount) <= 0) {
      context.addIssue({ code: "custom", path: ["observedCryptoAmount"], message: "Enter a valid observed crypto amount or leave it blank." });
    }
  }
  if (value.confirmationCount) {
    const confirmations = Number(value.confirmationCount);
    if (!Number.isInteger(confirmations) || confirmations < 0) {
      context.addIssue({ code: "custom", path: ["confirmationCount"], message: "Enter a whole confirmation count or leave it blank." });
    }
  }
});
