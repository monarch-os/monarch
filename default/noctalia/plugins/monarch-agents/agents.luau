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
function M.stateDir(): string
  local stateHome = noctalia.getenv("XDG_STATE_HOME")
  if not stateHome or stateHome == "" then
    stateHome = noctalia.expandPath("~/.local/state")
  end
  return stateHome .. "/monarch/agents"
end

function M.usageDir(): string
  return M.stateDir() .. "/usage"
end

function M.disabledAgents(): { string }
  local dir = M.stateDir() .. "/disabled"
  local result: { string } = {}
  for _, entry in ipairs(noctalia.listDir(dir) or {}) do
    local name = if type(entry) == "table" then entry.name else entry
    if type(name) == "string" and string.match(name, "^[a-z][a-z0-9%-]*$") then
      table.insert(result, name)
    end
  end
  return result
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
  -- The billion step matters once the per-model chart shows real all-time
  -- totals: without it a heavy model reads "3485.9M".
  if n >= 1000000000 then
    return string.format("%.1fB", n / 1000000000)
  elseif n >= 1000000 then
    return string.format("%.1fM", n / 1000000)
  elseif n >= 1000 then
    return string.format("%.1fk", n / 1000)
  end
  return tostring(n)
end

function M.timestamp(value: string?): number?
  if type(value) ~= "string" or value == "" then
    return nil
  end
  local y, mo, d, h, mi, s = string.match(value, "^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then
    return nil
  end
  -- Noctalia's os.time interprets tables as UTC; formatTime applies local time.
  local utc = os.time({
    year = tonumber(y) :: number,
    month = tonumber(mo) :: number,
    day = tonumber(d) :: number,
    hour = tonumber(h) :: number,
    min = tonumber(mi) :: number,
    sec = tonumber(s) :: number,
    isdst = false,
  })
  local sign, hours, minutes = string.match(value, "([+-])(%d%d):(%d%d)$")
  if sign then
    local offset = ((tonumber(hours) :: number) * 60 + (tonumber(minutes) :: number)) * 60
    utc -= if sign == "+" then offset else -offset
  elseif not string.match(value, "Z$") then
    return nil
  end
  return utc
end

function M.formatReset(value: string?): string
  local stamp = M.timestamp(value)
  return if stamp then noctalia.formatTime("%a %H:%M", stamp) else ""
end

function M.limitPercent(limit: any): number
  local reset = M.timestamp(limit.resetsAt)
  if reset and reset * 1000 <= noctalia.nowMs() then
    return 0
  end
  return math.clamp(tonumber(limit.percent) or 0, 0, 1)
end

function M.freshness(record: any): string
  local stamp = M.timestamp(record.limitsFetchedAt or record.updatedAt)
  local prefix = if record.limitsStale == true then "Last known quotas" else "Quotas updated"
  if not stamp then
    return if record.limitsStale == true then prefix .. " · time unavailable" else ""
  end
  local minutes = math.max(0, math.floor((noctalia.nowMs() / 1000 - stamp) / 60))
  if minutes == 0 then
    return prefix .. " less than a minute ago"
  elseif minutes < 60 then
    return prefix .. " " .. minutes .. "m ago"
  end
  return prefix .. " " .. math.floor(minutes / 60) .. "h ago"
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
      local percent = M.limitPercent(limit)
      if percent > worst then
        worst = percent
      end
    end
  end
  return worst
end

return M
