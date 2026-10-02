export const MAX_REPORT_BYTES = 65536;

function object(value, keys) {
  if (!value || typeof value !== "object" || Array.isArray(value)
    || Object.keys(value).some(key => !keys.includes(key))
    || keys.some(key => !Object.hasOwn(value, key))) {
    throw new Error("Invalid report fields.");
  }
}

function text(value, maximum, empty = false) {
  if (typeof value !== "string" || value.length > maximum || (!empty && !value.length)
    || /[\x00-\x1f\x7f]/.test(value)) {
    throw new Error("Invalid report text.");
  }
  return value;
}

function choice(value, allowed) {
  if (!allowed.includes(value)) throw new Error("Invalid report value.");
  return value;
}

export function validateReport(value) {
  object(value, ["schema", "crash", "system", "package", "backtrace", "backtraceTruncated"]);
  object(value.crash, ["application", "date", "signal", "core", "truncated"]);
  object(value.system, ["monarch", "kernel", "architecture", "source"]);
  object(value.package, ["name", "version", "source"]);
  if (value.schema !== 1 || typeof value.crash.truncated !== "boolean"
    || typeof value.backtraceTruncated !== "boolean") throw new Error("Invalid report schema.");
  const date = text(value.crash.date, 20);
  if (!/^\d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC$/.test(date)) throw new Error("Invalid crash date.");
  const parsed = new Date(date.slice(0, 10) + "T" + date.slice(11, 16) + ":00Z");
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 16).replace("T", " ") !== date.slice(0, 16)) {
    throw new Error("Invalid crash date.");
  }
  if (!Array.isArray(value.backtrace) || value.backtrace.length > 120) throw new Error("Invalid backtrace.");
  const backtrace = value.backtrace.map(line => {
    text(line, 300);
    if (!/^(#[0-9]+\s|Stack trace|ELF object binary architecture:)/.test(line)) throw new Error("Invalid stack frame.");
    return line;
  });
  const application = text(value.crash.application, 256);
  if (application.includes("/") || application.includes("\\")) throw new Error("Expected an application name.");
  return {
    schema: 1,
    crash: {
      application, date, signal: text(value.crash.signal, 64),
      core: choice(value.crash.core, ["present", "truncated", "missing", "unavailable"]),
      truncated: value.crash.truncated,
    },
    system: {
      monarch: text(value.system.monarch, 256), kernel: text(value.system.kernel, 256),
      architecture: text(value.system.architecture, 64), source: choice(value.system.source, ["current"]),
    },
    package: {
      name: text(value.package.name, 256, true), version: text(value.package.version, 256, true),
      source: choice(value.package.source, ["journal", "installed"]),
    },
    backtrace, backtraceTruncated: value.backtraceTruncated,
  };
}

export async function hash(value) {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

export async function fingerprint(report) {
  const frames = report.backtrace.filter(line => /^#[0-9]+\s/.test(line))
    .slice(0, 8).map(line => line.replace(/^#[0-9]+\s+/, "").replace(/0x[0-9a-f]+\s+/gi, ""));
  return hash(JSON.stringify([report.crash.application, report.crash.signal,
    report.package.name, report.package.version, frames]));
}

export function receipt(id, origin) {
  return { reference: "MCR-" + id.slice(0, 16).toUpperCase(),
    url: new URL(`/admin/reports/${id}`, origin).href };
}
