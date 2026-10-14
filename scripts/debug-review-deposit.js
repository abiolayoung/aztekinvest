const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "..", ".env.local") });
const { Client } = require("pg");

async function main() {
  const c = new Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });
  await c.connect();

  const fn = await c.query(`
    select pg_get_functiondef(p.oid) as def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'review_deposit'
  `);
  console.log(fn.rows[0]?.def || "MISSING");

  const deps = await c.query(`
    select id, reference, status, user_id, receipt_path is not null as has_receipt,
           transaction_hash, requested_amount_cents, credited_amount_cents
    from public.deposit_requests
    order by created_at desc
    limit 8
  `);
  console.log("DEPOSITS", deps.rows);
  await c.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
