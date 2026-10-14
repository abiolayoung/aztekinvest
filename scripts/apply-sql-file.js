const fs = require("fs");
const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "..", ".env.local") });
const { Client } = require("pg");

const file = process.argv[2];
if (!file) {
  console.error("Usage: node scripts/apply-sql-file.js <path-to.sql>");
  process.exit(1);
}

async function main() {
  const sql = fs.readFileSync(path.resolve(file), "utf8");
  const c = new Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });
  await c.connect();
  await c.query(sql);
  console.log("APPLIED", file);
  await c.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
