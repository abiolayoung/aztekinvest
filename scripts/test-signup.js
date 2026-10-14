const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "..", ".env.local") });

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
const email = `aztek.signup.${Date.now()}@mailinator.com`;
const password = "TestPass1234!x";

async function main() {
  const createRes = await fetch(`${url}/auth/v1/admin/users`, {
    method: "POST",
    headers: {
      apikey: service,
      Authorization: `Bearer ${service}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: "Wire Test", country_code: "US" },
    }),
  });
  const created = await createRes.json();
  if (!createRes.ok) {
    console.error("CREATE_FAIL", createRes.status, created);
    process.exit(1);
  }
  const userId = created.id;
  console.log("CREATED", email, userId);

  const bonusRes = await fetch(`${url}/rest/v1/rpc/grant_signup_bonus`, {
    method: "POST",
    headers: {
      apikey: service,
      Authorization: `Bearer ${service}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ target_user: userId }),
  });
  if (!bonusRes.ok) {
    console.error("BONUS_FAIL", bonusRes.status, await bonusRes.text());
  } else {
    console.log("BONUS_OK");
  }

  const profileRes = await fetch(
    `${url}/rest/v1/profiles?id=eq.${userId}&select=id,full_name,role,account_status`,
    {
      headers: {
        apikey: service,
        Authorization: `Bearer ${service}`,
      },
    }
  );
  console.log("PROFILE", await profileRes.json());

  const acctRes = await fetch(
    `${url}/rest/v1/account_ledger_accounts?account_owner_user_id=eq.${userId}&select=account_type`,
    {
      headers: {
        apikey: service,
        Authorization: `Bearer ${service}`,
      },
    }
  );
  console.log("ACCOUNTS", await acctRes.json());

  const txRes = await fetch(
    `${url}/rest/v1/ledger_transactions?source_id=eq.${userId}&transaction_type=eq.signup_bonus&select=transaction_type,description,idempotency_key`,
    {
      headers: {
        apikey: service,
        Authorization: `Bearer ${service}`,
      },
    }
  );
  console.log("BONUS_TX", await txRes.json());
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
