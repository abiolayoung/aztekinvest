import { readFileSync, readdirSync } from "fs";
import path from "path";
import { describe, expect, it } from "vitest";
import { destinationAddressError, transactionHashError } from "@/lib/security/sensitive";
import { registerSchema } from "@/lib/validation/schemas";

describe("sensitive input", () => {
  it("rejects seed phrases and private keys as destinations", () => {
    expect(destinationAddressError("abandon ability able about above absent absorb abstract absurd abuse access accident")).not.toBeNull();
    expect(destinationAddressError("a".repeat(64))).not.toBeNull();
    expect(destinationAddressError(`0x${"ab".repeat(32)}`)).not.toBeNull();
  });

  it("accepts a public-style address and a transaction hash", () => {
    expect(destinationAddressError(`0x${"ab".repeat(20)}`)).toBeNull();
    expect(transactionHashError(`0x${"ab".repeat(32)}`)).toBeNull();
  });
});

describe("registration", () => {
  it("requires terms and cannot carry a role", () => {
    const parsed = registerSchema.safeParse({
      fullName: "Amina Cole",
      email: "amina@example.com",
      password: "Correct-Horse-19",
      confirmPassword: "Correct-Horse-19",
      countryCode: "US",
      acceptTerms: true,
      role: "admin",
    });
    expect(parsed.success).toBe(true);
    if (parsed.success) expect(parsed.data).not.toHaveProperty("role");
  });
});

describe("database safety", () => {
  const sql = readdirSync(path.join(process.cwd(), "supabase/migrations"))
    .filter((file) => file.endsWith(".sql"))
    .map((file) => readFileSync(path.join(process.cwd(), "supabase/migrations", file), "utf8"))
    .join("\n");

  it("enables and forces row level security on every table", () => {
    const tables = [...sql.matchAll(/create table public\.(\w+)/g)].map((match) => match[1]);
    expect(tables.length).toBeGreaterThan(10);
    for (const table of tables) {
      expect(sql).toContain(`alter table public.${table} enable row level security`);
      expect(sql).toContain(`alter table public.${table} force row level security`);
    }
  });

  it("does not create a column for private keys", () => {
    expect(sql).not.toMatch(/private_key\s+text/i);
    expect(sql).not.toMatch(/seed_phrase\s+text/i);
  });

  it("keeps deposit credit behind an administrator review function", () => {
    expect(sql).toContain("function public.review_deposit");
    expect(sql).toContain("deposit-credit:");
  });
});
