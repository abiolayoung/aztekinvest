import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import pg from "pg";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const envPath = path.join(root, ".env.local");
for (const line of fs.readFileSync(envPath, "utf8").split(/\r?\n/)) {
  const match = line.match(/^([A-Z0-9_]+)=(.*)$/);
  if (!match || process.env[match[1]]) continue;
  process.env[match[1]] = match[2];
}

const rawPassword = process.env.SUPABASE_DB_PASSWORD ?? "";
const password = encodeURIComponent(rawPassword);
const projectRef = new URL(process.env.NEXT_PUBLIC_SUPABASE_URL).hostname.split(".")[0];
const regions = [
  "eu-central-1",
  "eu-west-1",
  "eu-west-2",
  "us-east-1",
  "us-east-2",
  "us-west-1",
  "ap-southeast-1",
  "ap-northeast-1",
];

const candidates = [
  `postgresql://postgres:${password}@db.${projectRef}.supabase.co:5432/postgres`,
  `postgresql://postgres:${password}@db.${projectRef}.supabase.co:6543/postgres`,
  ...regions.flatMap((region) => [
    `postgresql://postgres.${projectRef}:${password}@aws-0-${region}.pooler.supabase.com:6543/postgres`,
    `postgresql://postgres.${projectRef}:${password}@aws-0-${region}.pooler.supabase.com:5432/postgres`,
    `postgresql://postgres:${password}@aws-0-${region}.pooler.supabase.com:6543/postgres`,
  ]),
];

const migrationsDir = path.join(root, "supabase", "migrations");
const files = fs.readdirSync(migrationsDir).filter((name) => name.endsWith(".sql")).sort();

async function connect() {
  const errors = [];
  for (const connectionString of candidates) {
    const client = new pg.Client({
      connectionString,
      ssl: { rejectUnauthorized: false },
      connectionTimeoutMillis: 8000,
    });
    try {
      await client.connect();
      console.log(`Connected via ${connectionString.replaceAll(password, "***").replaceAll(rawPassword, "***")}`);
      return client;
    } catch (error) {
      errors.push(`${connectionString.split("@")[1]} => ${error.message}`);
      try {
        await client.end();
      } catch {
        /* ignore */
      }
    }
  }
  console.error(errors.slice(0, 12).join("\n"));
  throw new Error("Could not connect to Supabase Postgres with the provided password.");
}

const client = await connect();
try {
  await client.query(`
    create table if not exists public.schema_migrations (
      filename text primary key,
      applied_at timestamptz not null default now()
    );
  `);

  for (const filename of files) {
    const { rows } = await client.query(
      "select 1 from public.schema_migrations where filename = $1",
      [filename],
    );
    if (rows.length) {
      console.log(`skip ${filename}`);
      continue;
    }
    const sql = fs.readFileSync(path.join(migrationsDir, filename), "utf8");
    console.log(`apply ${filename}`);
    await client.query("begin");
    try {
      await client.query(sql);
      await client.query("insert into public.schema_migrations (filename) values ($1)", [filename]);
      await client.query("commit");
      console.log(`ok ${filename}`);
    } catch (error) {
      await client.query("rollback");
      throw error;
    }
  }
  console.log("Migrations complete.");
} finally {
  await client.end();
}
