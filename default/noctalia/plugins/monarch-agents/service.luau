--!strict
-- The data side, formerly Main.qml + Agent.qml.
--
-- Discovery is decoupled from collection, as in v4: listing the usage directory
-- costs nothing so it runs every minute, while the expensive collector keeps
-- its 15-minute cadence. Without that split an agent configured mid-session
-- would stay invisible for a full interval and read as broken.
--
-- v4 watched each record with a FileView and reacted to writes. v5 plugins have
-- no file watcher, so the minute tick re-reads the records instead — the same
-- freshness for a directory that holds a handful of small files.

local agents = require("./agents.luau")

local TICK_MS = 60000

local refreshIntervalSec = tonumber(noctalia.getConfig("refresh_interval_sec")) or 900
if refreshIntervalSec < 60 then
  refreshIntervalSec = 60
end

local lastCollectMs = 0
local collecting = false
-- A collector that could not reach its limits endpoint at all — typically the
-- seconds after login before the network is up — writes retryAdvised into its
-- record. Honour it with one sooner try rather than waiting out the full
-- interval. Only the advising agents rerun, so an outage at one provider does
-- not put every other collector on a treadmill.
local retryAtMs = 0
local retryIds: { string } = {}

noctalia.setUpdateInterval(TICK_MS)

-- ------------------------------------------------------------------ reading

local function readRecords(): { any }
  local dir = agents.usageDir()
  local entries = noctalia.listDir(dir)
  if not entries then
    return {}
  end

  local names: { string } = {}
  for _, entry in ipairs(entries) do
    local name = if type(entry) == "table" then entry.name else entry
    if type(name) == "string" and string.sub(name, -5) == ".json" then
      table.insert(names, name)
    end
  end
  table.sort(names)

  local records = {}
  for _, name in ipairs(names) do
    local content = noctalia.readFile(dir .. "/" .. name)
    if content then
      local parsed = noctalia.json.decode(content)
      -- Only "ready" records can be drawn; a half-written one is skipped
      -- rather than rendered as zeroes.
      if type(parsed) == "table" and parsed.ready == true then
        table.insert(records, parsed)
      end
    end
  end
  return records
end

local function publish(records: { any })
  noctalia.state.set(agents.KEY_RECORDS, records)
  noctalia.state.set(agents.KEY_WORST, agents.worstPercent(records))

  -- Re-arm the short retry for whichever agents asked for one.
  local advising: { string } = {}
  for _, record in ipairs(records) do
    if record.retryAdvised == true then
      table.insert(advising, tostring(record.id))
    end
  end
  retryIds = advising
  retryAtMs = if #advising > 0 then noctalia.nowMs() + 30000 else 0
end

-- ---------------------------------------------------------------- collecting

-- kind: "limits" for the cheap cadence, "force" for an explicit refresh.
local function collect(kind: string, ids: { string }?)
  if collecting then
    return
  end
  collecting = true
  lastCollectMs = noctalia.nowMs()

  -- Absolute path on purpose: Noctalia's PATH does not carry Monarch's bin, so
  -- a bare command name would silently fail to launch.
  local root = noctalia.getenv("MONARCH_PATH")
  if not root or root == "" then
    root = "/usr/share/monarch"
  end
  local parts = { agents.shellQuote(root .. "/bin/monarch-agent-usage-update") }

  if kind == "force" then
    table.insert(parts, "--force")
  elseif kind == "limits" then
    table.insert(parts, "--limits-only")
  end
  for _, id in ipairs(ids or {}) do
    table.insert(parts, agents.shellQuote(id))
  end

  local started = noctalia.runAsync(table.concat(parts, " "), function(result)
    collecting = false
    if result.exitCode ~= 0 and result.stderr ~= "" then
      noctalia.log("agents: collector failed: " .. tostring(result.stderr))
    end
    publish(readRecords())
  end)

  if not started then
    collecting = false
    noctalia.log("agents: could not start the collector")
  end
end

-- ------------------------------------------------------------------ lifecycle

function update()
  local now = noctalia.nowMs()

  -- Cheap: always refresh what is on disk, so an agent that appeared between
  -- collector runs shows up within the minute.
  publish(readRecords())

  if retryAtMs > 0 and now >= retryAtMs and #retryIds > 0 then
    retryAtMs = 0
    collect("limits", retryIds)
    return
  end

  if now - lastCollectMs >= refreshIntervalSec * 1000 then
    collect("limits")
  end
end

-- The widget's right-click asks for a forced refresh through here, since only
-- the service owns the collector.
function onIpc(command: string)
  if command == "refresh" then
    collect("force")
  end
end
