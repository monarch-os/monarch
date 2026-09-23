--!nonstrict
-- The menu, reachable from the global launcher: typing `mm` in Mod+Space lists
-- every menu action, and picking one runs it without the panel ever opening.
--
-- Same data and visibility guards as the panel — both go through
-- `monarch-menu`, so a row hidden in the panel is hidden here too.

local model = require("./model.luau")

local MONARCH_BIN = "/usr/bin"

local menu = nil
local guards = {}
local loading = false
local query = ""

local function shellQuote(text)
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function monarchShell(command)
  return "bash -c " .. shellQuote("export PATH=" .. MONARCH_BIN .. ':"$PATH"\n' .. command)
end

local function publish(query)
  if not menu then
    launcher.setResults(query, {})
    return
  end

  local results = {}
  for _, hit in ipairs(model.search(menu, query, guards)) do
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

local function load()
  if loading then
    return
  end
  loading = true

  noctalia.runAsync(monarchShell("monarch-menu --launcher-state"), function(result)
    loading = false
    if result and result.exitCode == 0 then
      local payload = noctalia.json.decode(result.stdout or "")
      if type(payload) == "table" and type(payload.tree) == "table" then
        menu = model.fromArray(payload.tree)
        guards = payload.guards or {}
      end
    end
    publish(query)
  end)
end

function onQuery(text)
  query = text or ""
  menu = nil
  guards = {}
  launcher.setResults(query, {})
  load()
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
