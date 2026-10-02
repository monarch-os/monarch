import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, writeFile, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { report } from "./fixtures.js";

const service = fileURLToPath(new URL("..", import.meta.url));
const root = path.resolve(service, "../..");
const temporary = await mkdtemp(path.join(tmpdir(), "monarch-crash-integration-"));
const port = 18787;
const endpoint = `http://127.0.0.1:${port}`;
const env = { ...process.env, WRANGLER_SEND_METRICS: "false", WRANGLER_LOG_PATH: path.join(temporary, "wrangler.log") };
let server, output = "";

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: service, env, ...options });
    let stdout = "", stderr = "";
    child.stdout.on("data", data => { stdout += data; });
    child.stderr.on("data", data => { stderr += data; });
    child.on("error", reject);
    child.on("exit", code => code === 0 ? resolve(stdout) : reject(new Error(`${command} failed (${code}): ${stderr}`)));
  });
}

async function upload(key, value = report()) {
  return fetch(endpoint + "/v1/reports", { method: "POST",
    headers: { "Content-Type": "application/json", "Idempotency-Key": key }, body: JSON.stringify(value) });
}

try {
  const localConfig = JSON.parse(await readFile(path.join(service, "wrangler.jsonc"), "utf8"));
  localConfig.vars = { LOCAL_DEV: "true", INGEST_ENABLED: "true", DAILY_LIMIT: "1000", RETENTION_DAYS: "30" };
  localConfig.name = "monarch-crashes-integration";
  localConfig.main = path.join(service, "src/worker.js");
  localConfig.assets.directory = path.join(service, "public");
  localConfig.d1_databases[0].migrations_dir = path.join(service, "migrations");
  delete localConfig.env;
  delete localConfig.triggers;
  const config = path.join(temporary, "wrangler.json");
  await writeFile(config, JSON.stringify(localConfig));
  const wrangler = path.join(service, "node_modules/wrangler/bin/wrangler.js");
  await run(process.execPath, [wrangler, "d1", "migrations", "apply", "monarch-crashes", "--local", "--config", config,
    "--persist-to", path.join(temporary, "storage")]);
  server = spawn(process.execPath, [wrangler, "dev", "--local", "--ip", "127.0.0.1", "--port", String(port),
    "--config", config, "--persist-to", path.join(temporary, "storage")], { cwd: service, env });
  server.stdout.on("data", data => { output += data; });
  server.stderr.on("data", data => { output += data; });
  for (let attempt = 0; attempt < 100; attempt++) {
    if (server.exitCode !== null) throw new Error(output);
    try {
      const status = await fetch(endpoint + "/v1/status");
      assert.equal((await status.json()).enabled, true);
      break;
    } catch {
      if (attempt === 99) throw new Error("Local Worker did not start: " + output);
      await new Promise(resolve => setTimeout(resolve, 200));
    }
  }
  const key = crypto.randomUUID();
  const first = await upload(key);
  assert.equal(first.status, 201);
  const receipt = await first.json();
  assert.match(receipt.url, new RegExp(`^${endpoint}/admin/reports/[a-f0-9]{64}$`));
  const page = await fetch(receipt.url);
  assert.equal(page.status, 200);
  assert.match(page.headers.get("content-type"), /text\/html/);
  assert.match(await page.text(), /Copier le lien du crash/);
  assert.match(page.headers.get("content-security-policy"), /script-src 'self'/);
  for (const name of ["app.js", "style.css"]) {
    assert.equal((await fetch(endpoint + "/admin/" + name)).status, 200);
  }
  assert.deepEqual(await (await upload(key)).json(), receipt);
  assert.equal((await upload(crypto.randomUUID())).status, 201);
  const groups = await (await fetch(endpoint + "/admin/api/groups")).json();
  assert.equal(groups.totals.reports, 2);
  assert.equal(groups.groups[0].occurrences, 2);
  const reports = await (await fetch(endpoint + "/admin/api/groups/" + groups.groups[0].fingerprint)).json();
  const detail = await (await fetch(endpoint + "/admin/api/reports/" + reports.reports[0].id)).json();
  assert.deepEqual(detail.report, report());

  const journal = path.join(temporary, "journalctl");
  await writeFile(journal, `#!/bin/bash\nprintf '%s\\n' '${JSON.stringify({
    _BOOT_ID: "0123456789abcdef0123456789abcdef", COREDUMP_UID: String(process.getuid()),
    COREDUMP_PID: "42", COREDUMP_TIMESTAMP: "1790943000000000", COREDUMP_EXE: "/usr/bin/kitty",
    COREDUMP_SIGNAL_NAME: "SIGSEGV", COREDUMP_PACKAGE_NAME: "kitty", COREDUMP_PACKAGE_VERSION: "0.44.0-1",
    MESSAGE: "Stack trace of thread 42:\n#0 fail (libkitty.so + 0x10)",
  })}'\n`, { mode: 0o755 });
  const clientEnv = { ...env, MONARCH_PATH: root, MONARCH_CRASH_ENDPOINT: endpoint, MONARCH_CRASH_ALLOW_LOCAL: "1",
    XDG_STATE_HOME: path.join(temporary, "state"), XDG_CONFIG_HOME: path.join(temporary, "config"),
    PATH: temporary + path.delimiter + process.env.PATH };
  const id = "0123456789abcdef0123456789abcdef:42:1790943000000000";
  const binary = path.join(root, "bin/monarch-crash-submit");
  const preview = JSON.parse(await run(binary, ["prepare", id], { env: clientEnv }));
  const sent = JSON.parse(await run(binary, ["send", id, "--confirm"], { env: clientEnv }));
  assert.match(sent.reference, /^MCR-[A-F0-9]{16}$/);
  const sentId = new URL(sent.url).pathname.split("/").pop();
  const sentDetail = await (await fetch(endpoint + "/admin/api/reports/" + sentId)).json();
  assert.deepEqual(sentDetail.report, preview.report);
  assert.equal(sentDetail.url, sent.url);
  assert.deepEqual(JSON.parse(await run(binary, ["send", id, "--confirm"], { env: clientEnv })), sent);
  const after = await (await fetch(endpoint + "/admin/api/groups")).json();
  assert.equal(after.totals.reports, 3);
  const all = (await Promise.all(after.groups.map(async group =>
    (await (await fetch(endpoint + "/admin/api/groups/" + group.fingerprint)).json()).reports))).flat();
  const entries = await Promise.all(all.map(async entry =>
    (await (await fetch(endpoint + "/admin/api/reports/" + entry.id)).json())));
  assert.deepEqual(entries.find(entry => entry.reference === sent.reference).report, preview.report);
  const stopped = new Promise(resolve => server.once("exit", resolve));
  server.kill("SIGTERM");
  await stopped;
  localConfig.vars.LOCAL_DEV = "false";
  await writeFile(config, JSON.stringify(localConfig));
  server = spawn(process.execPath, [wrangler, "dev", "--local", "--ip", "127.0.0.1", "--port", String(port),
    "--config", config, "--persist-to", path.join(temporary, "storage")], { cwd: service, env });
  server.stdout.on("data", data => { output += data; });
  server.stderr.on("data", data => { output += data; });
  for (let attempt = 0; attempt < 100; attempt++) {
    if (server.exitCode !== null) throw new Error(output);
    try {
      const denied = await fetch(endpoint + "/admin/api/groups");
      assert.equal(denied.status, 403);
      break;
    } catch {
      if (attempt === 99) throw new Error("Production Access boundary failed: " + output);
      await new Promise(resolve => setTimeout(resolve, 200));
    }
  }
  for (const path of [new URL(receipt.url).pathname, "/admin/", "/admin/app.js", "/admin/style.css"]) {
    assert.equal((await fetch(endpoint + path)).status, 403);
  }
  console.log("Local Worker, real D1/R2 bindings, grouping, Access boundary and Bash client round trip pass.");
} finally {
  if (server && server.exitCode === null) {
    const ended = new Promise(resolve => server.once("exit", resolve));
    server.kill("SIGTERM");
    await ended;
  }
  await rm(temporary, { recursive: true, force: true });
}
