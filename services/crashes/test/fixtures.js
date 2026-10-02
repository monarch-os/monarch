import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";

export function report() {
  return {
    schema: 1,
    crash: { application: "kitty", date: "2026-10-02 12:10 UTC", signal: "SIGSEGV", core: "present", truncated: false },
    system: { monarch: "5.0.0", kernel: "6.18.0", architecture: "x86_64", source: "current" },
    package: { name: "kitty", version: "0.44.0-1", source: "journal" },
    backtrace: ["Stack trace:", "#0 fail (libkitty.so + 0x10)", "#1 main (kitty + 0x20)"],
    backtraceTruncated: false,
  };
}

export function environment() {
  const sqlite = new DatabaseSync(":memory:");
  sqlite.exec(readFileSync(new URL("../migrations/0001_reports.sql", import.meta.url), "utf8"));
  const objects = new Map();
  return {
    INGEST_ENABLED: "true", DAILY_LIMIT: "1000", RETENTION_DAYS: "30",
    DB: {
      prepare(query) {
        const statement = sqlite.prepare(query);
        let values = [];
        const bound = {
          bind(...parameters) { values = parameters; return bound; },
          async first() { return statement.get(...values) || null; },
          async all() { return { results: statement.all(...values) }; },
          async run() { return statement.run(...values); },
        };
        return bound;
      },
    },
    REPORTS: {
      async put(key, value) { objects.set(key, value); },
      async get(key) { return objects.has(key) ? { text: async () => objects.get(key) } : null; },
      async delete(key) { objects.delete(key); },
    },
    INGEST_LIMITER: { async limit() { return { success: true }; } },
    ASSETS: {
      async fetch(request) {
        const name = new URL(request.url).pathname.split("/").pop();
        return new Response(readFileSync(new URL(`../public/admin/${name}`, import.meta.url)), {
          headers: { "Content-Type": name.endsWith("html") ? "text/html" : "text/plain" },
        });
      },
    },
    sqlite, objects,
  };
}

export function submission(value = report(), id = crypto.randomUUID(), headers = {}) {
  return new Request("https://crashes.example.com/v1/reports", {
    method: "POST", headers: { "Content-Type": "application/json", "Idempotency-Key": id, ...headers },
    body: JSON.stringify(value),
  });
}
