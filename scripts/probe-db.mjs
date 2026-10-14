import pg from "pg";

const password = encodeURIComponent("ableGOD200**");
const ref = "qozkvhralwkulhuzqeza";
const ips = ["52.59.152.35", "18.198.30.239", "18.198.145.223"];
const hosts = [
  "aws-0-eu-central-1.pooler.supabase.com",
  "aws-0-eu-central-2.pooler.supabase.com",
  "aws-0-eu-west-1.pooler.supabase.com",
  "aws-0-us-east-1.pooler.supabase.com",
  "aws-1-eu-central-1.pooler.supabase.com",
  "aws-1-us-east-1.pooler.supabase.com",
];

for (const host of hosts) {
  for (const hostaddr of ips) {
    for (const user of [`postgres.${ref}`, "postgres"]) {
      for (const port of [6543, 5432]) {
        const client = new pg.Client({
          user,
          password: "ableGOD200**",
          host: hostaddr,
          port,
          database: "postgres",
          ssl: { rejectUnauthorized: false, servername: host },
          connectionTimeoutMillis: 4000,
        });
        try {
          await client.connect();
          console.log("SUCCESS", { host, hostaddr, user, port });
          await client.end();
          process.exit(0);
        } catch (error) {
          console.log("fail", host, port, user, String(error.message).slice(0, 100));
          try {
            await client.end();
          } catch {
            /* ignore */
          }
        }
      }
    }
  }
}
console.log("no connection");
process.exit(1);
