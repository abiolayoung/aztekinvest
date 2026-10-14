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
    where n.nspname = 'public' and p.proname = 'mark_deposit_paid'
  `);
  console.log("FN_COUNT", fn.rowCount);
  if (fn.rows[0]) {
    console.log("--- FUNCTION ---");
    console.log(fn.rows[0].def);
  }

  const deps = await c.query(`
    select id, reference, status, user_id, receipt_path, created_at
    from public.deposit_requests
    order by created_at desc
    limit 5
  `);
  console.log("RECENT_DEPOSITS", deps.rows);

  const grants = await c.query(`
    select grantee, privilege_type
    from information_schema.routine_privileges
    where routine_schema = 'public' and routine_name = 'mark_deposit_paid'
  `);
  console.log("GRANTS", grants.rows);

  await c.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
