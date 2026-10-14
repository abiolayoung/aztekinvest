const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "..", ".env.local") });
const { Client } = require("pg");

async function main() {
  const c = new Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });
  await c.connect();

  const pol = await c.query(`
    select polname, polcmd,
           pg_get_expr(polqual, polrelid) as using_expr,
           pg_get_expr(polwithcheck, polrelid) as check_expr
    from pg_policy
    where polrelid = 'public.deposit_requests'::regclass
  `);
  console.log("POLICIES", JSON.stringify(pol.rows, null, 2));

  const na = await c.query(`
    select pg_get_functiondef(oid) as def
    from pg_proc
    where proname = 'notify_admins' and pronamespace = 'public'::regnamespace
  `);
  console.log("notify_admins has row_security off?", /row_security/.test(na.rows[0]?.def || ""));

  const uid = "842a8646-7487-41b6-8fbd-70599eb10f3b";
  const did = "c4839ced-2bbd-4363-8927-7e0148eed73a";

  await c.query("begin");
  await c.query("select set_config('request.jwt.claim.sub', $1, true)", [uid]);
  await c.query("select set_config('request.jwt.claims', $1, true)", [
    JSON.stringify({ sub: uid, role: "authenticated" }),
  ]);
  await c.query("set local role authenticated");
  try {
    await c.query("select public.mark_deposit_paid($1,$2,$3,$4,$5)", [
      did,
      `${uid}/${did}/test-receipt.jpg`,
      "test-receipt.jpg",
      "image/jpeg",
      null,
    ]);
    console.log("CALL_OK");
  } catch (e) {
    console.log("CALL_FAIL", e.message);
  }
  await c.query("rollback");
  await c.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
