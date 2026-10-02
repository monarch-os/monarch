import { authorize, localRequest } from "./access.js";
import { MAX_REPORT_BYTES, validateReport, hash, fingerprint, receipt } from "./report.js";

const securityHeaders = {
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
};

function json(value, status = 200, headers = {}) {
  return Response.json(value, { status, headers: { ...securityHeaders, ...headers } });
}

function configuration(env) {
  const daily = Number(env.DAILY_LIMIT);
  const retention = Number(env.RETENTION_DAYS);
  return Number.isInteger(daily) && daily > 0 && daily <= 10000
    && Number.isInteger(retention) && retention > 0 && retention <= 90
    && env.DB && env.REPORTS && env.INGEST_LIMITER;
}

async function readReport(request) {
  if (!(request.headers.get("Content-Type") || "").match(/^application\/json(?:\s*;|$)/i)) {
    return { error: "Expected application/json.", status: 415 };
  }
  if (Number(request.headers.get("Content-Length")) > MAX_REPORT_BYTES) {
    return { error: "Report exceeds 64 KiB.", status: 413 };
  }
  const reader = request.body?.getReader();
  if (!reader) return { error: "Missing report.", status: 400 };
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_REPORT_BYTES) {
        await reader.cancel();
        return { error: "Report exceeds 64 KiB.", status: 413 };
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    return { report: validateReport(JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes))) };
  } catch {
    return { error: "Invalid crash report.", status: 400 };
  }
}

async function ingest(request, env) {
  if (env.INGEST_ENABLED !== "true" || !configuration(env)) return json({ error: "Collection unavailable." }, 503);
  if (request.headers.has("Origin")) return json({ error: "Use the Monarch client." }, 403);
  const actor = request.headers.get("CF-Connecting-IP") || (localRequest(request, env) ? "local" : "unknown");
  const { success } = await env.INGEST_LIMITER.limit({ key: actor });
  if (!success) return json({ error: "Too many reports. Try later." }, 429, { "Retry-After": "60" });
  const submission = request.headers.get("Idempotency-Key") || "";
  if (!/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(submission)) {
    return json({ error: "Expected a submission UUID." }, 400);
  }
  const data = await readReport(request);
  if (data.error) return json({ error: data.error }, data.status);
  const payload = JSON.stringify(data.report);
  const id = await hash(submission);
  const payloadHash = await hash(payload);
  const previous = await env.DB.prepare("SELECT state, payload_hash FROM reports WHERE id = ?").bind(id).first();
  if (previous) {
    if (previous.payload_hash !== payloadHash) return json({ error: "Submission content has changed." }, 409);
    return previous.state === "ready" ? json(receipt(id, request.url))
      : json({ error: "This report is being received. Try again shortly." }, 409, { "Retry-After": "5" });
  }
  const now = new Date().toISOString();
  const budget = await env.DB.prepare(`INSERT INTO daily_budget(day, used) VALUES(?, 1)
    ON CONFLICT(day) DO UPDATE SET used = used + 1 WHERE used < ? RETURNING used`)
    .bind(now.slice(0, 10), Number(env.DAILY_LIMIT)).first();
  if (!budget) return json({ error: "Today's collection limit has been reached." }, 429, { "Retry-After": "3600" });
  const report = data.report;
  const group = await fingerprint(report);
  const claimed = await env.DB.prepare(`INSERT INTO reports
    (id, payload_hash, fingerprint, application, crash_date, signal, package_version, monarch_version, received_at, state)
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending') ON CONFLICT(id) DO NOTHING RETURNING id`)
    .bind(id, payloadHash, group, report.crash.application, report.crash.date, report.crash.signal,
      report.package.version, report.system.monarch, now).first();
  if (!claimed) return json({ error: "This report is being received. Try again shortly." }, 409, { "Retry-After": "5" });
  try {
    await env.REPORTS.put(`reports/${id}.json`, payload, { httpMetadata: { contentType: "application/json" } });
  } catch (error) {
    await env.DB.prepare("DELETE FROM reports WHERE id = ? AND state = 'pending'").bind(id).run();
    throw error;
  }
  await env.DB.prepare("UPDATE reports SET state = 'ready' WHERE id = ?").bind(id).run();
  return json(receipt(id, request.url), 201);
}

async function asset(request, env, name) {
  const url = new URL(request.url);
  url.pathname = `/admin/${name}`;
  url.search = "";
  const response = await env.ASSETS.fetch(new Request(url, { method: "GET" }));
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(securityHeaders)) headers.set(key, value);
  headers.set("Content-Security-Policy", "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
  return new Response(response.body, { status: response.status, headers });
}

async function admin(request, env, path) {
  if (!await authorize(request, env)) return json({ error: "Maintainer access required." }, 403);
  if (request.method !== "GET") return json({ error: "Method not allowed." }, 405, { Allow: "GET" });
  if (path === "/admin") return new Response(null, { status: 302, headers: { ...securityHeaders, Location: "/admin/" } });
  if (path === "/admin/" || /^\/admin\/reports\/[a-f0-9]{64}$/.test(path)) {
    return asset(request, env, "index.html");
  }
  if (["/admin/app.js", "/admin/style.css"].includes(path)) return asset(request, env, path.split("/").pop());
  if (path === "/admin/api/groups") {
    const offset = Math.max(0, Math.min(100000, Number(new URL(request.url).searchParams.get("offset")) || 0));
    const { results } = await env.DB.prepare(`SELECT fingerprint, application, signal, package_version,
      COUNT(*) AS occurrences, MAX(received_at) AS last_received
      FROM reports WHERE state = 'ready' GROUP BY fingerprint
      ORDER BY last_received DESC, fingerprint LIMIT 51 OFFSET ?`).bind(Math.floor(offset)).all();
    const totals = await env.DB.prepare(`SELECT COUNT(*) AS reports, COUNT(DISTINCT fingerprint) AS groups
      FROM reports WHERE state = 'ready'`).first();
    return json({ groups: results.slice(0, 50), hasMore: results.length > 50, totals,
      retentionDays: Number(env.RETENTION_DAYS) });
  }
  const group = path.match(/^\/admin\/api\/groups\/([a-f0-9]{64})$/);
  if (group) {
    const { results } = await env.DB.prepare(`SELECT id, crash_date, monarch_version, received_at
      FROM reports WHERE state = 'ready' AND fingerprint = ? ORDER BY received_at DESC LIMIT 50`)
      .bind(group[1]).all();
    return json({ reports: results });
  }
  const detail = path.match(/^\/admin\/api\/reports\/([a-f0-9]{64})$/);
  if (detail) {
    const row = await env.DB.prepare("SELECT id FROM reports WHERE id = ? AND state = 'ready'").bind(detail[1]).first();
    if (!row) return json({ error: "Report not found." }, 404);
    const report = await env.REPORTS.get(`reports/${row.id}.json`);
    if (!report) return json({ error: "Report unavailable." }, 404);
    return json({ ...receipt(row.id, request.url), report: JSON.parse(await report.text()),
      retentionDays: Number(env.RETENTION_DAYS) });
  }
  return json({ error: "Not found." }, 404);
}

export async function expire(env, now = new Date()) {
  if (!configuration(env)) throw new Error("Invalid collection configuration.");
  const cutoff = new Date(now.getTime() - Number(env.RETENTION_DAYS) * 86400000).toISOString();
  const stale = new Date(now.getTime() - 3600000).toISOString();
  const { results } = await env.DB.prepare(`SELECT id FROM reports WHERE received_at < ?
    OR (state = 'pending' AND received_at < ?) ORDER BY received_at LIMIT 500`).bind(cutoff, stale).all();
  // Delete the object before its index so a failed deletion remains retryable.
  for (const row of results) {
    await env.REPORTS.delete(`reports/${row.id}.json`);
    await env.DB.prepare("DELETE FROM reports WHERE id = ?").bind(row.id).run();
  }
  await env.DB.prepare("DELETE FROM daily_budget WHERE day < ?").bind(now.toISOString().slice(0, 10)).run();
}

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;
    try {
      if (path === "/v1/status" && request.method === "GET") {
        return json({ schema: 1, enabled: env.INGEST_ENABLED === "true" && Boolean(configuration(env)),
          retentionDays: Number(env.RETENTION_DAYS) || 30, maxBytes: MAX_REPORT_BYTES });
      }
      if (path === "/v1/reports") {
        return request.method === "POST" ? await ingest(request, env)
          : json({ error: "Method not allowed." }, 405, { Allow: "POST" });
      }
      if (path === "/admin" || path.startsWith("/admin/")) return await admin(request, env, path);
      return json({ error: "Not found." }, 404);
    } catch {
      return json({ error: "Collection temporarily unavailable." }, 503);
    }
  },
  async scheduled(_event, env) {
    await expire(env);
  },
};
