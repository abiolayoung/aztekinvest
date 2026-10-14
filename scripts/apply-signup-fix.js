const fs = require("fs");
const path = require("path");
const { Client } = require("pg");

try {
  require("dotenv").config({ path: path.join(__dirname, "..", ".env.local") });
} catch {
  // optional
}

const url =
  process.env.DATABASE_URL ||
  (() => {
    const pwd = encodeURIComponent(process.env.SUPABASE_DB_PASSWORD || "");
    if (!pwd) throw new Error("Set DATABASE_URL or SUPABASE_DB_PASSWORD in .env.local");
    return (
      "postgresql://postgres.qozkvhralwkulhuzqeza:" +
      pwd +
      "@aws-1-eu-central-1.pooler.supabase.com:6543/postgres"
    );
  })();

async function main() {
  const sqlPath = path.join(__dirname, "..", "supabase", "FIX_SIGNUP_NOW.sql");
  const sql = fs.readFileSync(sqlPath, "utf8");
  const c = new Client({
    connectionString: url,
    ssl: { rejectUnauthorized: false },
    connectionTimeoutMillis: 20000,
  });
  await c.connect();
  console.log("connected");
  await c.query(sql);
  console.log("FIX_SIGNUP_NOW applied");
  await c.end();
}

main().catch((e) => {
  console.error("ERR", e.message);
  process.exit(1);
});
