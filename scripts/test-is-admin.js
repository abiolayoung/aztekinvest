const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "..", ".env.local") });
const { Client } = require("pg");

async function main() {
  const c = new Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });
  await c.connect();

  const admin = await c.query(`
    select id, role, account_status from public.profiles where role = 'admin' limit 1
  `);
  console.log("ADMIN_ROW", admin.rows[0]);
  const uid = admin.rows[0]?.id;
  if (!uid) {
    console.error("no admin");
    process.exit(1);
  }

  await c.query("begin");
  await c.query("select set_config('request.jwt.claim.sub', $1, true)", [uid]);
  await c.query("select set_config('request.jwt.claims', $1, true)", [
    JSON.stringify({ sub: uid, role: "authenticated" }),
  ]);
  await c.query("set local role authenticated");

  const check = await c.query("select auth.uid() as uid, public.is_admin() as is_admin");
  console.log("CHECK", check.rows[0]);

  // Try review without fix first? Apply fix then test
  await c.query("rollback");
  await c.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
