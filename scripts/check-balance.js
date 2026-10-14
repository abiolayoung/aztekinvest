const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "..", ".env.local") });
const { Client } = require("pg");

const userId = process.argv[2] || "43d4e9e0-c877-43ea-9a42-c2df4582bb85";

async function main() {
  const c = new Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });
  await c.connect();
  const r = await c.query(
    `select a.account_type,
      coalesce(sum(e.credit_amount),0) - coalesce(sum(e.debit_amount),0) as balance_cents
     from account_ledger_accounts a
     left join ledger_entries e on e.account_id = a.id
     where a.account_owner_user_id = $1
     group by a.account_type
     order by a.account_type`,
    [userId]
  );
  console.log(r.rows);
  await c.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
