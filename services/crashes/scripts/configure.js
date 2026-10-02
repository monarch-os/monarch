import { readFileSync, writeFileSync } from "node:fs";

const file = process.argv[2];
if (!file) throw new Error("Usage: node scripts/configure.js <terraform-crash-collection.json>");
const infra = JSON.parse(readFileSync(file, "utf8"));
if (!infra || !/^[a-f0-9]{32}$/.test(infra.account_id)
  || !/^[a-f0-9-]{36}$/.test(infra.database_id)
  || !/^[a-z0-9-]+\.monarchlinux\.com$/.test(infra.hostname)
  || !/^[a-z0-9-]+\.cloudflareaccess\.com$/.test(infra.team_domain)
  || typeof infra.access_aud !== "string" || !infra.access_aud.length
  || !Number.isInteger(infra.daily_limit) || infra.daily_limit < 1 || infra.daily_limit > 10000
  || !Number.isInteger(infra.retention_days) || infra.retention_days < 1 || infra.retention_days > 90
  || infra.bucket_name !== "monarch-crashes" || infra.database_name !== "monarch-crashes") {
  throw new Error("Invalid infrastructure configuration.");
}
const config = JSON.parse(readFileSync(new URL("../wrangler.jsonc", import.meta.url), "utf8"));
delete config.env;
config.account_id = infra.account_id;
config.routes = [{ pattern: infra.hostname, custom_domain: true }];
config.d1_databases[0].database_id = infra.database_id;
config.vars = {
  INGEST_ENABLED: "false",
  DAILY_LIMIT: String(infra.daily_limit),
  RETENTION_DAYS: String(infra.retention_days),
  ACCESS_TEAM_DOMAIN: infra.team_domain,
  ACCESS_AUD: infra.access_aud,
};
writeFileSync(new URL("../wrangler.production.json", import.meta.url), JSON.stringify(config, null, 2) + "\n");
console.log("Production configuration prepared with ingestion disabled.");
