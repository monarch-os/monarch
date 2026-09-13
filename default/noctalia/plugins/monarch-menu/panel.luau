--!nonstrict
-- The Monarch menu as a Noctalia panel. Replaces the fuzzel renderer in
-- bin/monarch-menu, which is now only an IPC wrapper: the tree still comes from
-- default/monarch/monarch-menu.jsonc, and all of the parsing, route resolution
-- and guard batching lives in model.luau next door.
--
-- The shell runs without Monarch's bin on PATH, so every action and every guard
-- is launched through a shell with that directory prepended — see monarchBin.

local model = require("./model.luau")

local HOME = noctalia.getenv("HOME") or ""
local MONARCH_BIN = "/usr/bin"

local menu = nil
local guards = {}
local stack = { "root" }
local rows = {}
local cursor = 1
local cursors = {}
local query = ""
local searchRevision = 0
local status = "Loading the menu…"
-- Set the moment the user does anything with the panel. The state refresh lands
-- after the first frame is already on screen and interactive, so it must correct
-- the data under them rather than yank them back to the route they opened on.
local interacted = false
-- Provider rows are fetched per level and cached until another level is opened.
local providerRows = {}
local providerFor = nil
local mode = "menu"
local requestActive = false
local requestPrompt = ""
local selectionFile = ""
local doneFile = ""
local choices = {}

local function shellQuote(text: string): string
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

-- Anything Monarch ships is resolved from its own bin, which the shell's own
-- PATH does not include.
local function monarchShell(command: string): string
  return "bash -c " .. shellQuote("export PATH=" .. MONARCH_BIN .. ':"$PATH"\n' .. command)
end

local function currentLevel(): string
  return stack[#stack]
end

-- Noctalia's ui.scroll is a scroll container, not a list view: it can be pinned
-- to the bottom and it reports its offset, but nothing scrolls it to a child.
-- So the panel draws only the slice of rows the viewport holds and moves that
-- slice with the cursor — arrowing past the fold shifts the window instead of
-- leaving the selection somewhere off screen.
--
-- Sizes measured in the 560px panel: a level's one-line rows are ~39px, a search
-- result's two lines ~52px. Deliberately one short of what fits, so the slice
-- never overflows the viewport: ui.scroll has no prop to hide its scrollbar or
-- to refuse the wheel, and an overflowing slice would show a bar reporting the
-- slice rather than the list — contradicting the count in the header, and
-- letting the wheel shift the view out from under the window.
local WINDOW_ROWS = 10
local WINDOW_ROWS_SEARCHING = 6

local windowStart = 1

local function windowRows(): number
  return if query ~= "" then WINDOW_ROWS_SEARCHING else WINDOW_ROWS
end

local function revealCursor()
  local size = windowRows()
  if cursor < windowStart then
    windowStart = cursor
  elseif cursor > windowStart + size - 1 then
    windowStart = cursor - size + 1
  end
  windowStart = math.min(windowStart, math.max(1, #rows - size + 1))
  windowStart = math.max(windowStart, 1)
end

-- Rows are uniform whichever level they come from: an entry row carries an id,
-- a provider row carries the value the provider will be handed back. Cursor,
-- rendering and activation only ever see this shape.
local function entryRows(ids: { string })
  local out = {}
  for _, id in ids do
    table.insert(out, { kind = "entry", id = id })
  end
  return out
end

local function hitRows(hits)
  local out = {}
  local previousGroup = nil
  for _, hit in hits do
    table.insert(out, {
      kind = "entry",
      id = hit.id,
      group = hit.group,
      groupStart = hit.group ~= previousGroup,
    })
    previousGroup = hit.group
  end
  return out
end

local function choiceRows(options)
  local out = {}
  for index, option in options do
    local parts = option:split("\t")
    local glyph = ""
    local label = parts[1] or ""
    local detail = ""
    local value = label
    if #parts >= 2 then
      glyph = parts[1]
      label = parts[2]
      value = label
    end
    if #parts >= 3 then
      detail = parts[3]
      value = label .. "\t" .. detail
    end
    table.insert(out, {
      kind = "choice",
      id = "choice-" .. tostring(index),
      glyph = glyph,
      label = label,
      detail = detail,
      value = value,
      searchText = label .. " " .. detail,
    })
  end
  return out
end

local function refreshRows()
  if mode == "input" then
    rows = {}
  elseif mode == "select" then
    rows = {}
    for _, choice in choices do
      if query == "" or noctalia.fuzzyScore(query, choice.searchText) then
        table.insert(rows, choice)
      end
    end
  elseif query ~= "" then
    rows = hitRows(model.search(menu, query, guards, currentLevel()))
  elseif providerFor == currentLevel() then
    rows = providerRows
  else
    rows = entryRows(model.visibleChildren(menu, currentLevel(), guards))
  end

  if cursor > #rows then
    cursor = #rows
  end
  if cursor < 1 then
    cursor = 1
  end
  windowStart = 1
end

local render

-- Tree and guards come back together, on every open. Caching the tree across
-- opens *instead* of re-reading it would be wrong: editing monarch-menu.jsonc, or
-- the user's own extension, would then change nothing until the shell restarted.
-- Guards have to be re-read every time anyway, so this costs one subprocess, not
-- two. What the previous open left in `menu`/`guards` is still used to paint the
-- first frame — see onOpen — but it is never what the panel settles on.
local function refreshState(onDone)
  noctalia.runAsync(monarchShell("monarch-menu --state"), function(result)
    if not result or result.exitCode ~= 0 then
      status = "monarch-menu --state failed"
      render()
      return
    end

    local payload = noctalia.json.decode(result.stdout or "")
    if type(payload) ~= "table" then
      status = "The menu data did not parse"
      render()
      return
    end

    local parsed = model.fromArray(payload.tree)
    if not parsed then
      status = "The menu data did not parse"
      render()
      return
    end

    menu = parsed
    -- Already an object keyed `<id>:<w|c|d>`: decoded natively, never parsed here.
    guards = payload.guards or {}

    if onDone then
      onDone()
    end
  end)
end

local function refreshInitial(context, onDone)
  noctalia.runAsync(monarchShell("monarch-menu --initial " .. shellQuote(context or "")), function(result)
    if not result or result.exitCode ~= 0 then
      status = "monarch-menu --initial failed"
      render()
      onDone(false)
      return
    end

    local payload = noctalia.json.decode(result.stdout or "")
    local parsed = type(payload) == "table" and model.fromArray(payload) or nil
    if not parsed then
      status = "The menu data did not parse"
      render()
      onDone(false)
      return
    end

    menu = parsed
    guards = {}
    onDone(true)
  end)
end

local function providerRowFor(row, index: number)
  return ui.row({
    key = "value:" .. row.value,
    gap = 10,
    align = "center",
    padding = 8,
    radius = 8,
    -- "primary/0" and not nil: the host only applies a prop that is present,
    -- and for row/column there is no clear-on-absence path (only drop_zone has
    -- one), so dropping the key leaves the previous fill painted. Every row the
    -- cursor passed through then stays highlighted.
    fill = index == cursor and "primary/0.12" or "primary/0",
    onClick = function()
      cursor = index
      activate()
    end,
  }, {
    ui.label({ text = row.label, flexGrow = 1, color = "on_surface" }),
    row.current and ui.label({ text = "✓", color = "primary" }) or ui.label({ text = "" }),
  })
end

local function rowFor(row, index: number)
  if row.kind == "choice" then
    local naming = ui.label({ text = row.label, flexGrow = 1, color = "on_surface" })
    if row.detail ~= "" then
      naming = ui.column({ flexGrow = 1, gap = 1 }, {
        ui.label({ text = row.label, color = "on_surface" }),
        ui.label({ text = row.detail, fontSize = 11, color = "on_surface/0.55", maxLines = 1 }),
      })
    end
    return ui.row({
      key = row.id,
      gap = 10,
      align = "center",
      padding = 8,
      radius = 8,
      fill = index == cursor and "primary/0.12" or "primary/0",
      onClick = function()
        cursor = index
        activate()
      end,
    }, {
      ui.label({ text = row.glyph, width = 22, color = "on_surface" }),
      naming,
    })
  end

  if row.kind == "value" then
    return providerRowFor(row, index)
  end

  local id = row.id
  local entry = menu.entries[id]
  local selected = index == cursor
  local isDisabled = entry.disabled and entry.disabled ~= "" and guards[id .. ":d"] == true
  local isChecked = isDisabled
    or (entry.checked and entry.checked ~= "" and guards[id .. ":c"] == true)

  local label = model.labelOf(menu, id)
  local tint = isDisabled and "on_surface_variant" or "on_surface"

  -- While searching, rows come from the whole tree, so each one says where it
  -- lives — otherwise three rows called "PHP" are indistinguishable. The path
  -- goes under the name, smaller and faded: run together on one line the two
  -- read as a single string and neither reads as a name.
  local naming = ui.label({ text = label, flexGrow = 1, color = tint })
  if query ~= "" then
    local parent = model.parentOf(menu, id)
    local detail = entry.description
    if not detail or detail == "" then
      detail = if parent ~= "root" then model.breadcrumb(menu, parent) else nil
    end
    if detail then
      naming = ui.column({ flexGrow = 1, gap = 1 }, {
        ui.label({ text = label, color = tint }),
        ui.label({
          text = detail,
          fontSize = 11,
          color = "on_surface/0.55",
          maxLines = 1,
        }),
      })
    end
  elseif isDisabled then
    naming = ui.column({ flexGrow = 1, gap = 1 }, {
      ui.label({ text = label, color = tint }),
      ui.label({
        text = entry.disabledLabel or "Installed",
        fontSize = 11,
        color = "on_surface/0.55",
        maxLines = 1,
      }),
    })
  end

  local children = {
    ui.label({ text = entry.icon or "", width = 22, color = tint }),
    naming,
  }

  if isChecked then
    table.insert(children, ui.label({ text = "✓", color = "primary" }))
  elseif not entry.action then
    table.insert(children, ui.label({ text = "›", color = "on_surface_variant" }))
  end

  -- The row is its own highlight: `ui.box` takes no children, so wrapping one
  -- around the row silently drops everything inside it.
  return ui.row({
    key = id,
    gap = 10,
    align = "center",
    padding = 8,
    radius = 8,
    -- "primary/0" and not nil: the host only applies a prop that is present,
    -- and for row/column there is no clear-on-absence path (only drop_zone has
    -- one), so dropping the key leaves the previous fill painted. Every row the
    -- cursor passed through then stays highlighted.
    fill = selected and "primary/0.12" or "primary/0",
    onClick = isDisabled and nil or function()
      cursor = index
      activate()
    end,
  }, children)
end

-- The window hides the scrollbar's meaning, so the header carries the position
-- instead: without it, nine results out of forty look like all of them.
local function headerText(): string
  if mode ~= "menu" then
    if mode == "select" and query ~= "" then
      local noun = if #rows == 1 then "result" else "results"
      return requestPrompt .. "  ·  " .. tostring(#rows) .. " " .. noun
    end
    return requestPrompt
  end

  local level = currentLevel()
  local where = if query == "" then
      model.breadcrumb(menu, level)
    elseif level == "root" then "Search"
    else "Search in " .. model.breadcrumb(menu, level)
  if query ~= "" then
    local noun = if #rows == 1 then "result" else "results"
    return where .. "  ·  " .. tostring(#rows) .. " " .. noun
  end
  if #rows > windowRows() then
    return where .. "  ·  " .. tostring(cursor) .. "/" .. tostring(#rows)
  end
  return where
end

function render()
  if mode == "menu" and not menu then
    panel.render(ui.column({ flexGrow = 1, gap = 12 }, {
      ui.label({ text = status, color = "on_surface_variant" }),
    }))
    return
  end

  local children = {}
  if #rows == 0 and mode ~= "input" then
    table.insert(children, ui.label({ text = "Nothing here", color = "on_surface_variant" }))
  else
    revealCursor()
    for index = windowStart, math.min(#rows, windowStart + windowRows() - 1) do
      local row = rows[index]
      if mode == "menu" and query ~= "" and (row.groupStart or index == windowStart) then
        table.insert(children, ui.label({
          text = model.titleOf(menu, row.group),
          fontSize = 11,
          fontWeight = "bold",
          color = "primary",
          padding = 4,
        }))
      end
      table.insert(children, rowFor(row, index))
    end
  end

  panel.render(ui.column({ flexGrow = 1, gap = 10 }, {
    ui.row({ align = "center", gap = 8 }, {
      ui.label({
        text = headerText(),
        fontSize = 15,
        fontWeight = "bold",
        color = "on_surface",
        flexGrow = 1,
      }),
      ui.button({ glyph = "close", onClick = "onCloseClicked" }),
    }),

    ui.input({
      key = "search-" .. searchRevision,
      placeholder = if mode == "menu" then "Search the menu…" else requestPrompt .. "…",
      focus = true,
      onChange = "onQueryChanged",
      onSubmit = "onQuerySubmitted",
    }),

    ui.scroll({ flexGrow = 1, gap = 2, align = "stretch" }, children),

    ui.row({ align = "center", gap = 14 }, {
      ui.label({
        text = if mode == "input" then "↵ Confirm" else "↑↓ Navigate",
        fontSize = 11,
        color = "on_surface/0.55",
      }),
      mode ~= "input" and ui.label({ text = "↵ Open", fontSize = 11, color = "on_surface/0.55" })
        or ui.label({ text = "Esc Cancel", fontSize = 11, color = "on_surface/0.55" }),
      mode == "menu" and ui.label({ text = "← Back", fontSize = 11, color = "on_surface/0.55" })
        or ui.label({ text = "" }),
    }),
  }))
end

-- ── Navigation ───────────────────────────────────────────────────────────────

-- Provider rows only exist at runtime, so they are fetched when their level is
-- opened rather than held with the tree. The cursor lands on the current value,
-- which is what the fuzzel renderer got from --select.
local function fetchProvider(id: string)
  providerFor = nil
  providerRows = {}

  noctalia.runAsync(monarchShell("monarch-menu --provider " .. shellQuote(id)), function(result)
    if not result or result.exitCode ~= 0 then
      return
    end

    local decoded = noctalia.json.decode(result.stdout or "")
    if type(decoded) ~= "table" then
      return
    end

    local out = {}
    for _, item in decoded do
      table.insert(out, { kind = "value", label = item.label, value = item.value, current = item.current })
    end

    providerRows = out
    providerFor = id
    cursor = 1
    for index, row in out do
      if row.current then
        cursor = index
        break
      end
    end

    refreshRows()
    render()
  end)
end

local function enter(id: string)
  stack = { "root" }
  local segments = {}
  local walk = id
  while walk ~= "root" do
    table.insert(segments, 1, walk)
    walk = model.parentOf(menu, walk)
  end
  for _, segment in segments do
    table.insert(stack, segment)
  end
  cursor = cursors[id] or 1

  local entry = menu.entries[id]
  if entry and entry.provider then
    fetchProvider(id)
  end
end

local function descend(id: string)
  table.insert(stack, id)
  cursor = cursors[id] or 1

  local entry = menu.entries[id]
  if entry and entry.provider then
    fetchProvider(id)
  end
end

local function runEntry(id: string)
  local entry = menu.entries[id]
  if not entry or not entry.action then
    return
  end
  noctalia.runAsync(monarchShell(entry.action))
  panel.close()
end

local function finishRequest(value: string?)
  if not requestActive then
    panel.close()
    return
  end

  local activeSelection = selectionFile
  local activeDone = doneFile
  requestActive = false
  selectionFile = ""
  doneFile = ""
  if value ~= nil then
    noctalia.writeFile(activeSelection, value .. "\n")
  end
  noctalia.writeFile(activeDone, "")
  panel.close()
end

function activate()
  interacted = true

  if mode == "input" then
    finishRequest(query)
    return
  end

  local row = rows[cursor]
  if not row then
    return
  end

  if row.kind == "choice" then
    finishRequest(row.value)
    return
  end

  -- A provider row hands its value straight back to the provider that produced
  -- it; the mapping from provider name to command lives in bin/monarch-menu.
  if row.kind == "value" then
    noctalia.runAsync(monarchShell(
      "monarch-menu --provider-set " .. shellQuote(providerFor) .. " " .. shellQuote(row.value)
    ))
    panel.close()
    return
  end

  local id = row.id
  local entry = menu.entries[id]
  if not entry then
    return
  end

  if entry.disabled and entry.disabled ~= "" and guards[id .. ":d"] == true then
    return
  end

  if entry.action then
    runEntry(id)
    return
  end

  local destination = entry.target or id
  local fromSearch = query ~= ""
  -- Leaving search mode: the row was found across the tree, so the level it
  -- opens is wherever it actually lives.
  query = ""
  searchRevision += 1
  cursors[currentLevel()] = cursor
  if fromSearch then
    enter(destination)
  else
    descend(destination)
  end
  refreshRows()
  render()
end

local function back(): boolean
  interacted = true

  if query ~= "" then
    query = ""
    searchRevision += 1
    refreshRows()
    render()
    return true
  end

  if #stack <= 1 then
    return false
  end

  table.remove(stack)
  cursor = cursors[currentLevel()] or 1
  refreshRows()
  render()
  return true
end

local function moveCursor(delta: number)
  interacted = true

  if #rows == 0 then
    return
  end
  cursor += delta
  if cursor < 1 then
    cursor = #rows
  elseif cursor > #rows then
    cursor = 1
  end
  render()
end

-- ── Host callbacks ───────────────────────────────────────────────────────────

local function openAt(context: string?)
  mode = "menu"
  local route = model.resolveRoute(menu, context)

  if route ~= "root" and not menu.entries[route] then
    noctalia.notifyError("Unknown menu route", route)
    panel.close()
    return
  end

  local entry = route ~= "root" and menu.entries[route] or nil
  -- A route that names an action runs it rather than opening an empty level.
  if entry and entry.action then
    runEntry(route)
    return
  end

  if entry and entry.target then
    route = entry.target
  end

  query = ""
  searchRevision += 1
  enter(route)
  refreshRows()
  render()
end

local function openRequest(payload)
  mode = payload.mode == "input" and "input" or "select"
  requestPrompt = tostring(payload.prompt or (mode == "input" and "Input" or "Select"))
  selectionFile = tostring(payload.selectionFile or "")
  doneFile = tostring(payload.doneFile or "")
  requestActive = doneFile ~= ""
  choices = choiceRows(type(payload.options) == "table" and payload.options or {})
  query = ""
  cursor = 1
  searchRevision += 1
  interacted = false
  refreshRows()
  render()
end

local function requestPayload(context)
  if type(context) ~= "string" or context == "" then
    return nil
  end
  local payload = noctalia.json.decode(context)
  if type(payload) == "table" and (payload.mode == "select" or payload.mode == "input") then
    return payload
  end
  return nil
end

local pendingContext = nil

-- Whether last open's tree is safe to draw this route from, before the fresh
-- state lands. Navigating a level is: the worst a stale guard does is show a row
-- that turns out to be hidden, which the refresh corrects a moment later. Running
-- an action is not — it would fire a command chosen on stale guards, and twice,
-- since the refresh re-runs the route. An unknown route is not either: it pops an
-- error and closes, which fresh data may well disprove. Both wait.
local function canPaintFromRetained(context): boolean
  if not menu then
    return false
  end

  local route = model.resolveRoute(menu, context)
  if route == "root" then
    return true
  end

  local entry = menu.entries[route]
  return entry ~= nil and entry.action == nil
end

function onOpen(context)
  local payload = requestPayload(context)
  if payload then
    openRequest(payload)
    return
  end

  pendingContext = context
  interacted = false
  -- Provider rows belong to the previous open, whichever path draws this one.
  providerFor = nil
  providerRows = {}

  local function settleState()
    if interacted then
      -- They have already typed or moved. Re-entering the route here would throw
      -- that away, so only the data underneath them is refreshed.
      refreshRows()
      render()
      return
    end
    providerFor = nil
    providerRows = {}
    openAt(pendingContext)
  end

  if canPaintFromRetained(context) then
    openAt(context)
    refreshState(settleState)
  elseif menu then
    refreshState(settleState)
  else
    render()
    refreshInitial(context, function(loaded)
      if not loaded then
        return
      end
      if canPaintFromRetained(context) then
        openAt(context)
      end
      refreshState(settleState)
    end)
  end
end

function onQueryChanged(value)
  interacted = true
  query = value or ""
  cursor = 1
  refreshRows()
  render()
end

function onQuerySubmitted(_value)
  activate()
end

function onKey(chord, pressed)
  if not pressed or (mode == "menu" and not menu) then
    return
  end

  if chord == "down" or chord == "ctrl+j" then
    moveCursor(1)
  elseif chord == "up" or chord == "ctrl+k" then
    moveCursor(-1)
  elseif chord == "return" or chord == "right" then
    activate()
  elseif chord == "left" then
    back()
  elseif chord == "escape" then
    if mode ~= "menu" then
      panel.close()
    elseif not back() then
      panel.close()
    end
  end
end

function onClose()
  if requestActive then
    local activeDone = doneFile
    requestActive = false
    selectionFile = ""
    doneFile = ""
    noctalia.writeFile(activeDone, "")
  end
  mode = "menu"
  choices = {}
end

function onCloseClicked()
  panel.close()
end

-- `monarch menu <route>` reaches the panel through this when it is already
-- open, so a second keybind press re-routes instead of doing nothing.
function onIpc(event, payload)
  if event == "open" then
    local request = requestPayload(payload)
    if request then
      openRequest(request)
    else
      openAt(payload)
    end
  end
end
