import test from "node:test";
import assert from "node:assert/strict";
import worker, { expire } from "../src/worker.js";
import { validateReport, fingerprint, hash } from "../src/report.js";
import { report, environment, submission } from "./fixtures.js";
import { authorize } from "../src/access.js";
import { generateKeyPair, exportJWK, SignJWT } from "jose";

test("stores only the validated report and returns a stable receipt on retry", async () => {
  const env = environment();
  const key = crypto.randomUUID();
  const first = await worker.fetch(submission(report(), key), env);
  assert.equal(first.status, 201);
  const receipt = await first.json();
  assert.match(receipt.reference, /^MCR-[A-F0-9]{16}$/);
  assert.equal(receipt.url, `https://crashes.example.com/admin/reports/${await hash(key)}`);
  const retry = await worker.fetch(submission(report(), key), env);
  assert.equal(retry.status, 200);
  assert.deepEqual(await retry.json(), receipt);
  assert.equal(env.objects.size, 1);
  assert.deepEqual(JSON.parse([...env.objects.values()][0]), report());
  assert.equal(env.sqlite.prepare("SELECT used FROM daily_budget").get().used, 1);
  assert.equal(first.headers.get("cache-control"), "no-store");
});

test("separate submissions with identical reports count as distinct occurrences", async () => {
  const env = environment();
  const receipts = await Promise.all([worker.fetch(submission(), env), worker.fetch(submission(), env)]);
  assert.notEqual((await receipts[0].json()).url, (await receipts[1].json()).url);
  assert.equal(env.objects.size, 2);
  assert.equal(env.sqlite.prepare("SELECT COUNT(DISTINCT fingerprint) AS n FROM reports").get().n, 1);
});

test("concurrent retries store one object and changed retry content is refused", async () => {
  const env = environment();
  const key = crypto.randomUUID();
  const results = await Promise.all([worker.fetch(submission(report(), key), env), worker.fetch(submission(report(), key), env)]);
  assert(results.some(response => response.status === 201));
  assert(results.every(response => [200, 201, 409].includes(response.status)));
  assert.equal(env.objects.size, 1);
  const changed = report();
  changed.system.monarch = "different";
  assert.equal((await worker.fetch(submission(changed, key), env)).status, 409);
});

test("extra sensitive fields, malformed dates, oversized bodies and browser uploads are rejected", async () => {
  const env = environment();
  for (const modify of [
    value => { value.environment = "SECRET"; },
    value => { value.crash.hostname = "private-host"; },
    value => { value.crash.date = "2026-02-31 12:10 UTC"; },
    value => { value.backtrace = ["TOKEN=secret"]; },
    value => { value.backtrace = ["#0 fail\u0000"]; },
    value => { value.backtrace = Array(121).fill("#0 fail"); },
    value => { value.system.source = "crash"; },
  ]) {
    const value = report(); modify(value);
    assert.equal((await worker.fetch(submission(value), env)).status, 400);
  }
  assert.equal((await worker.fetch(submission(report(), crypto.randomUUID(), { Origin: "https://example.com" }), env)).status, 403);
  assert.equal((await worker.fetch(submission(report(), "not-a-uuid"), env)).status, 400);
  const huge = new Request("https://crashes.example.com/v1/reports", {
    method: "POST", headers: { "Content-Type": "application/json", "Idempotency-Key": crypto.randomUUID() },
    body: " ".repeat(65537),
  });
  assert.equal((await worker.fetch(huge, env)).status, 413);
  assert.equal(env.objects.size, 0);
  assert.equal(env.sqlite.prepare("SELECT COUNT(*) AS n FROM daily_budget").get().n, 0);
});

test("collection configuration and both rate limits stop writes", async () => {
  const env = environment();
  env.INGEST_ENABLED = "false";
  assert.equal((await worker.fetch(submission(), env)).status, 503);
  env.INGEST_ENABLED = "true";
  env.DAILY_LIMIT = "1";
  await worker.fetch(submission(), env);
  assert.equal((await worker.fetch(submission(), env)).status, 429);
  assert.equal(env.objects.size, 1);
  env.INGEST_LIMITER.limit = async () => ({ success: false });
  const limited = await worker.fetch(submission(), env);
  assert.equal(limited.status, 429);
  assert.equal(limited.headers.get("retry-after"), "60");
});

test("concurrent requests cannot exceed the daily reservation budget", async () => {
  const env = environment();
  env.DAILY_LIMIT = "1";
  const results = await Promise.all(Array.from({ length: 5 }, () => worker.fetch(submission(), env)));
  assert.equal(results.filter(response => response.status === 201).length, 1);
  assert.equal(env.objects.size, 1);
});

test("storage failures remain retryable without exposing database errors", async () => {
  const env = environment();
  const put = env.REPORTS.put;
  env.REPORTS.put = async () => { throw new Error("private infrastructure detail"); };
  const key = crypto.randomUUID();
  const failed = await worker.fetch(submission(report(), key), env);
  assert.equal(failed.status, 503);
  assert(!JSON.stringify(await failed.json()).includes("private"));
  assert.equal(env.sqlite.prepare("SELECT COUNT(*) AS n FROM reports").get().n, 0);
  env.REPORTS.put = put;
  assert.equal((await worker.fetch(submission(report(), key), env)).status, 201);
});

test("admin access fails closed and grouping/report retrieval works on loopback only", async () => {
  const env = environment();
  await worker.fetch(submission(), env);
  const publicUrl = "https://crashes.example.com/admin/api/groups";
  assert.equal((await worker.fetch(new Request(publicUrl), env)).status, 403);
  env.LOCAL_DEV = "true";
  assert.equal((await worker.fetch(new Request(publicUrl), env)).status, 403);
  assert.equal((await worker.fetch(new Request(publicUrl, { headers: { "Cf-Access-Authenticated-User-Email": "admin@example.com" } }), env)).status, 403);
  const response = await worker.fetch(new Request("http://127.0.0.1/admin/api/groups"), env);
  const groups = await response.json();
  assert.equal(groups.totals.reports, 1);
  assert.equal(groups.groups[0].occurrences, 1);
  const group = await worker.fetch(new Request("http://127.0.0.1/admin/api/groups/" + groups.groups[0].fingerprint), env);
  const id = (await group.json()).reports[0].id;
  const detail = await worker.fetch(new Request("http://127.0.0.1/admin/api/reports/" + id), env);
  assert.deepEqual((await detail.json()).report, report());
});

test("report links and all dashboard assets require maintainer access", async () => {
  const env = environment();
  const received = await (await worker.fetch(submission(), env)).json();
  const paths = ["/admin", "/admin/", new URL(received.url).pathname, "/admin/app.js", "/admin/style.css"];
  let assets = 0;
  const fetchAsset = env.ASSETS.fetch;
  env.ASSETS.fetch = request => { assets++; return fetchAsset(request); };
  for (const path of paths) {
    assert.equal((await worker.fetch(new Request("https://crashes.example.com" + path), env)).status, 403);
  }
  assert.equal(assets, 0);
  env.LOCAL_DEV = "true";
  const page = await worker.fetch(new Request("http://127.0.0.1" + paths[2]), env);
  assert.equal(page.status, 200);
  assert.match(await page.text(), /Copier le lien du crash/);
  assert.match(page.headers.get("content-security-policy"), /script-src 'self'/);
  assert.equal(page.headers.get("cache-control"), "no-store");
  for (const path of ["/admin/index.html", "/public/admin/index.html", "/admin/reports/invalid"]) {
    assert.equal((await worker.fetch(new Request("http://127.0.0.1" + path), env)).status, 404);
  }
  env.sqlite.prepare("DELETE FROM reports").run();
  const id = new URL(received.url).pathname.split("/").pop();
  assert.equal((await worker.fetch(new Request("http://127.0.0.1/admin/api/reports/" + id), env)).status, 404);
});

test("expiration removes old and abandoned objects, retains failed deletions for retry", async () => {
  const env = environment();
  const insert = env.sqlite.prepare(`INSERT INTO reports VALUES(?, 'payload', 'fingerprint', 'kitty',
    '2026-09-01 12:10 UTC', 'SIGSEGV', '1', '5', ?, ?)`);
  for (const [id, date, state] of [["old", "2026-08-01T00:00:00.000Z", "ready"],
    ["fresh", "2026-10-02T12:00:00.000Z", "ready"], ["pending", "2026-10-02T00:00:00.000Z", "pending"]]) {
    insert.run(id, date, state);
    env.objects.set(`reports/${id}.json`, "{}");
  }
  const remove = env.REPORTS.delete;
  env.REPORTS.delete = async () => { throw new Error("unavailable"); };
  await assert.rejects(expire(env, new Date("2026-10-02T13:00:00Z")));
  assert.equal(env.objects.size, 3);
  env.REPORTS.delete = remove;
  await expire(env, new Date("2026-10-02T13:00:00Z"));
  assert.deepEqual([...env.objects.keys()], ["reports/fresh.json"]);
  assert.equal(env.sqlite.prepare("SELECT COUNT(*) AS n FROM reports").get().n, 1);
});

test("fingerprint ignores crash time and Monarch version but separates packages and stacks", async () => {
  const one = report(), two = report();
  two.crash.date = "2026-10-01 12:10 UTC";
  two.system.monarch = "6.0.0";
  assert.equal(await fingerprint(one), await fingerprint(two));
  two.package.version = "0.45.0";
  assert.notEqual(await fingerprint(one), await fingerprint(two));
  assert.equal((await hash("test")).length, 64);
  assert.deepEqual(validateReport(one), one);
});

test("Access requires a signed, unexpired JWT for this application and issuer", async () => {
  const { privateKey, publicKey } = await generateKeyPair("RS256");
  const jwk = { ...await exportJWK(publicKey), kid: "test-key", alg: "RS256", use: "sig" };
  const team = "monarch-test.cloudflareaccess.com";
  const env = { ACCESS_TEAM_DOMAIN: team, ACCESS_AUD: "crash-dashboard" };
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async url => {
    assert.equal(String(url), `https://${team}/cdn-cgi/access/certs`);
    return Response.json({ keys: [jwk] });
  };
  try {
    const token = async (audience, issuer, expiration) => new SignJWT({ email: "maintainer@example.com" })
      .setProtectedHeader({ alg: "RS256", kid: "test-key" }).setSubject("test-maintainer")
      .setIssuer(issuer).setAudience(audience).setExpirationTime(expiration).sign(privateKey);
    const check = async value => authorize(new Request("https://crashes.example.com/admin/", {
      headers: { "Cf-Access-Jwt-Assertion": value },
    }), env);
    const valid = await token(env.ACCESS_AUD, `https://${team}`, "1h");
    assert.equal(await check(valid), true);
    assert.equal(await check(await token("other-app", `https://${team}`, "1h")), false);
    assert.equal(await check(await token(env.ACCESS_AUD, "https://other.cloudflareaccess.com", "1h")), false);
    assert.equal(await check(await token(env.ACCESS_AUD, `https://${team}`, 1)), false);
    assert.equal(await check(valid.slice(0, -10) + "tampered"), false);
    assert.equal(await authorize(new Request("https://crashes.example.com/admin/"), {}), false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
