const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "..", ".env.local") });
const { Client } = require("pg");

async function main() {
  const c = new Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });
  await c.connect();
  const r = await c.query(`
    select pg_get_functiondef(oid) as d
    from pg_proc
    where proname = 'is_admin' and pronamespace = 'public'::regnamespace
  `);
  console.log(r.rows[0]?.d);
  await c.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
