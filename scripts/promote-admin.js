const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "..", ".env.local") });
const { Client } = require("pg");

const email = process.argv[2] || "spayid7@gmail.com";
const password = process.argv[3] || process.env.ADMIN_BOOTSTRAP_PASSWORD;
if (!password) {
  console.error("Usage: node scripts/promote-admin.js <email> <password>");
  process.exit(1);
}

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

async function findUserByEmail(target) {
  for (let page = 1; page <= 20; page += 1) {
    const r = await fetch(`${url}/auth/v1/admin/users?page=${page}&per_page=200`, {
      headers: { apikey: key, Authorization: `Bearer ${key}` },
    });
    const j = await r.json();
    const users = j.users || [];
    const found = users.find((u) => String(u.email || "").toLowerCase() === target.toLowerCase());
    if (found) return found;
    if (!users.length) break;
  }
  return null;
}

async function main() {
  let user = null;
  const createRes = await fetch(`${url}/auth/v1/admin/users`, {
    method: "POST",
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: "Platform Admin", country_code: "US" },
    }),
  });
  const created = await createRes.json();
  if (createRes.ok) {
    user = created;
    console.log("CREATED", user.id);
  } else {
    console.log("create_note", createRes.status, created?.msg || created?.message || created);
    user = await findUserByEmail(email);
    if (!user) {
      console.error("USER_MISSING");
      process.exit(1);
    }
    const upd = await fetch(`${url}/auth/v1/admin/users/${user.id}`, {
      method: "PUT",
      headers: {
        apikey: key,
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ password, email_confirm: true }),
    });
    console.log("password_synced", upd.status);
  }

  const userId = user.id;
  const c = new Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });
  await c.connect();

  await c.query(
    `insert into public.profiles (
      id, full_name, country_code, role, account_status, verification_status,
      email_verified_at, onboarding_welcome_at, onboarding_completed_at
    ) values ($1, 'Platform Admin', 'US', 'admin', 'active', 'verified', now(), now(), now())
    on conflict (id) do update set
      role = 'admin',
      account_status = 'active',
      verification_status = 'verified',
      email_verified_at = coalesce(public.profiles.email_verified_at, now()),
      onboarding_welcome_at = coalesce(public.profiles.onboarding_welcome_at, now()),
      onboarding_completed_at = coalesce(public.profiles.onboarding_completed_at, now()),
      full_name = case when coalesce(public.profiles.full_name, '') = '' then 'Platform Admin' else public.profiles.full_name end`,
    [userId]
  );

  await c.query(
    `insert into public.account_ledger_accounts (account_owner_user_id, account_type)
     values ($1, 'client_cash'), ($1, 'client_cash_reserved'), ($1, 'client_investments')
     on conflict (account_owner_user_id, account_type) where account_owner_user_id is not null
     do nothing`,
    [userId]
  );

  const check = await c.query(
    `select id, role, account_status, verification_status,
            email_verified_at is not null as email_ok,
            onboarding_completed_at is not null as onboarded
     from public.profiles where id = $1`,
    [userId]
  );
  console.log("ADMIN", check.rows[0]);
  await c.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
