--!nonstrict
-- The menu, reachable from the global launcher: typing `mm` in Mod+Space lists
-- every menu action, and picking one runs it without the panel ever opening.
--
-- Same data and same guards as the panel — both go through `monarch-menu`, so a
-- row hidden in the panel is hidden here too. The tree is fetched once and kept:
-- onQuery fires per keystroke and must not shell out.

local model = require("./model.luau")

local HOME = noctalia.getenv("HOME") or ""
local MONARCH_BIN = HOME .. "/.local/share/monarch/bin"

local menu = nil
local guards = {}
local loading = false

local function shellQuote(text: string): string
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function monarchShell(command: string): string
  return "bash -c " .. shellQuote("export PATH=" .. MONARCH_BIN .. ':"$PATH"\n' .. command)
end

local function load(onDone)
  if loading then
    return
  end
  loading = true

  noctalia.runAsync(monarchShell("monarch-menu --state"), function(result)
    if result and result.exitCode == 0 then
      local payload = noctalia.json.decode(result.stdout or "")
      if type(payload) == "table" then
        menu = model.fromArray(payload.tree)
        guards = payload.guards or {}
      end
    end
    loading = false
    if onDone then
      onDone()
    end
  end)
end

local function publish(query: string)
  if not menu then
    launcher.setResults(query, {})
    return
  end

  local results = {}
  for _, hit in model.search(menu, query, guards) do
    local id = hit.id
    local entry = menu.entries[id]
    -- A disabled row is already-installed software: listed in the panel so the
    -- catalog stays complete, but there is nothing to run, so it is not offered
    -- here.
    if not (entry.disabled and entry.disabled ~= "" and guards[id .. ":d"] == true) then
      local parent = model.parentOf(menu, id)
      table.insert(results, {
        id = id,
        title = model.labelOf(menu, id),
        subtitle = parent ~= "root" and model.breadcrumb(menu, parent) or nil,
        glyph = "menu-2",
      })
    end
  end

  launcher.setResults(query, results)
end

function onQuery(text)
  local query = text or ""

  if not menu then
    load(function()
      publish(query)
    end)
    return
  end

  publish(query)
end

function onActivate(id)
  if not menu then
    return
  end

  local entry = menu.entries[id]
  if not entry then
    return
  end

  if entry.action then
    noctalia.runAsync(monarchShell(entry.action))
    return
  end

  -- A submenu or a provider has nothing to run: hand it to the panel, which is
  -- the surface that can render a level.
  noctalia.runAsync(monarchShell("monarch-menu " .. shellQuote(id)))
end
