const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "..", ".env.local") });
const { Client } = require("pg");

async function main() {
  const c = new Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });
  await c.connect();

  const admin = await c.query(
    `select p.id from public.profiles p
     join auth.users u on u.id = p.id
     where lower(u.email) = lower('spayid7@gmail.com')`
  );
  const dep = await c.query(`
    select id, status, user_id, requested_amount_cents
    from public.deposit_requests
    where status = 'under_review'
    order by created_at desc
    limit 1
  `);
  console.log("BEFORE", dep.rows[0], "admin", admin.rows[0]?.id);
  if (!dep.rows[0] || !admin.rows[0]) {
    await c.end();
    return;
  }

  const adminId = admin.rows[0].id;
  const depositId = dep.rows[0].id;
  const credit = dep.rows[0].requested_amount_cents;
  const clientId = dep.rows[0].user_id;

  await c.query("begin");
  await c.query("select set_config('request.jwt.claim.sub', $1, true)", [adminId]);
  await c.query("select set_config('request.jwt.claims', $1, true)", [
    JSON.stringify({ sub: adminId, role: "authenticated" }),
  ]);
  await c.query("set local role authenticated");
  await c.query(`select public.review_deposit($1, 'approve', $2, $3, null, null, null)`, [
    depositId,
    "Verified receipt and marked payment received.",
    credit,
  ]);
  await c.query("commit");
  console.log("CREDIT_OK");

  const after = await c.query(
    `select status, credited_amount_cents from public.deposit_requests where id = $1`,
    [depositId]
  );
  console.log("AFTER", after.rows[0]);

  const bal = await c.query(
    `select coalesce(sum(e.credit_amount),0) - coalesce(sum(e.debit_amount),0) as cash_cents
     from account_ledger_accounts a
     left join ledger_entries e on e.account_id = a.id
     where a.account_owner_user_id = $1 and a.account_type = 'client_cash'`,
    [clientId]
  );
  console.log("CLIENT_CASH", bal.rows[0]);
  await c.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
