--!strict
-- Shared vocabulary for the agents plugin: where the records live, the state
-- keys the service publishes on, and the formatters the widget and panel both
-- need. No I/O here beyond reading the usage directory.

local M = {}

-- State keys. The service owns them; widget and panel only read.
M.KEY_RECORDS = "agents.records"
M.KEY_WORST = "agents.worst"

-- monarch-agent-usage-update writes one JSON record per agent here. A record
-- that appears in this directory is an agent, whoever wrote it — the plugin
-- never learns how the numbers were made.
function M.usageDir(): string
  local stateHome = noctalia.getenv("XDG_STATE_HOME")
  if not stateHome or stateHome == "" then
    stateHome = noctalia.expandPath("~/.local/state")
  end
  return stateHome .. "/monarch/agents/usage"
end

function M.pluginRoot(): string
  return noctalia.pluginDir() or ""
end

-- The agent's brand mark. Agents shipping a white mark carry an `<id>-light`
-- twin for light themes; callers fall back to a glyph when the file is absent.
function M.markPath(agentId: string): string?
  if agentId == "" then
    return nil
  end
  local root = M.pluginRoot()
  if root == "" then
    return nil
  end
  local variant = if noctalia.isDarkMode() then "" else "-light"
  local candidate = root .. "/assets/" .. agentId .. variant .. ".svg"
  if noctalia.fileExists(candidate) then
    return candidate
  end
  -- A light twin is optional; fall back to the default mark before giving up.
  candidate = root .. "/assets/" .. agentId .. ".svg"
  if noctalia.fileExists(candidate) then
    return candidate
  end
  return nil
end

-- Single-quote a value for a shell command line. runAsync's argument-array
-- form would make this unnecessary, but it needs plugin_api 24 and this shell
-- caps at 23 — see the note in plugin.toml.
function M.shellQuote(value: string): string
  return "'" .. string.gsub(value, "'", "'\\''") .. "'"
end

-- ------------------------------------------------------------- formatting

function M.formatTokens(value: number): string
  local n = math.floor(tonumber(value) or 0)
  if n >= 1000000 then
    return string.format("%.1fM", n / 1000000)
  elseif n >= 1000 then
    return string.format("%.1fk", n / 1000)
  end
  return tostring(n)
end

-- "2026-08-17T02:59:59+00:00" -> "Mon 04:59" in local time. Anything
-- unparseable yields "", which the caller then omits entirely.
function M.formatReset(value: string?): string
  if type(value) ~= "string" or value == "" then
    return ""
  end
  local y, mo, d, h, mi = string.match(value, "^(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
  if not y then
    return ""
  end
  -- The records carry UTC timestamps, and this runtime's os.time reads a table
  -- as UTC rather than local — verified against a record whose window reset at
  -- 23:00Z, which renders as 01:00 in a UTC+2 session. So the epoch goes to
  -- formatTime unadjusted and formatTime alone does the zone conversion;
  -- correcting by hand here would double the offset.
  local utc = os.time({
    year = tonumber(y) :: number,
    month = tonumber(mo) :: number,
    day = tonumber(d) :: number,
    hour = tonumber(h) :: number,
    min = tonumber(mi) :: number,
    sec = 0,
    isdst = false,
  })
  return noctalia.formatTime("%a %H:%M", utc)
end

function M.dayLabel(value: string?): string
  if type(value) ~= "string" or value == "" then
    return ""
  end
  local y, mo, d = string.match(value, "^(%d+)-(%d+)-(%d+)")
  if not y then
    return value
  end
  local stamp = os.time({
    year = tonumber(y) :: number,
    month = tonumber(mo) :: number,
    day = tonumber(d) :: number,
    hour = 12,
    min = 0,
    sec = 0,
    isdst = false,
  })
  return noctalia.formatTime("%a", stamp)
end

-- Palette roles rather than hex, so the meters follow whatever scheme is
-- active. Mirrors the v4 severityColor thresholds.
function M.severityRole(percent: number): string
  if percent >= 0.9 then
    return "error"
  elseif percent >= 0.75 then
    return "tertiary"
  end
  return "primary"
end

-- The single worst utilization across every window of every agent — what the
-- bar pill reacts to. Returns -1 when nothing has reported a limit yet.
function M.worstPercent(records: { any }): number
  local worst = -1
  for _, record in ipairs(records) do
    for _, limit in ipairs(record.limits or {}) do
      local percent = tonumber(limit.percent)
      if percent and percent >= 0 and percent > worst then
        worst = percent
      end
    end
  end
  return worst
end

return M
