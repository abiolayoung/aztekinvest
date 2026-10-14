const fs = require("fs");
const path = require("path");
const { Client } = require("pg");

const env = fs.readFileSync(path.join(__dirname, "..", ".env.local"), "utf8");
const url = env.match(/^DATABASE_URL=(.*)$/m)[1].trim();
const email = process.argv[2];

(async () => {
  const client = new Client({ connectionString: url, ssl: { rejectUnauthorized: false } });
  await client.connect();
  const { rows } = await client.query(
    "select p.id, u.email, p.selected_plan, p.selected_plan_at from public.profiles p join auth.users u on u.id = p.id where u.email = $1",
    [email],
  );
  console.log(rows);
  await client.end();
})();
