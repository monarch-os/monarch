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
local MONARCH_BIN = HOME .. "/.local/share/monarch/bin"

local menu = nil
local guards = {}
local stack = { "root" }
local rows = {}
local cursor = 1
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
local WINDOW_ROWS = 11
local WINDOW_ROWS_SEARCHING = 8

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

-- Search hits arrive grouped. `deeper` rides along only so render can rule off
-- where the open level's own hits end; the rule is drawn between rows and never
-- becomes one, so the cursor cannot land on it.
local function hitRows(hits)
  local out = {}
  for _, hit in hits do
    table.insert(out, { kind = "entry", id = hit.id, deeper = hit.deeper })
  end
  return out
end

local function refreshRows()
  if query ~= "" then
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
    if parent ~= "root" then
      naming = ui.column({ flexGrow = 1, gap = 1 }, {
        ui.label({ text = label, color = tint }),
        ui.label({
          text = model.breadcrumb(menu, parent),
          fontSize = 11,
          color = "on_surface/0.55",
          maxLines = 1,
        }),
      })
    end
  end

  local children = {
    ui.label({ text = entry.icon or "", width = 22, color = tint }),
    naming,
  }

  if isChecked then
    table.insert(children, ui.label({ text = "✓", color = "primary" }))
  elseif not entry.action and not entry.target then
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
  local level = currentLevel()
  local where = if query == "" then
      model.breadcrumb(menu, level)
    elseif level == "root" then "Search"
    else "Search in " .. model.breadcrumb(menu, level)
  if #rows > windowRows() then
    return where .. "  ·  " .. tostring(cursor) .. "/" .. tostring(#rows)
  end
  return where
end

function render()
  if not menu then
    panel.render(ui.column({ flexGrow = 1, gap = 12 }, {
      ui.label({ text = status, color = "on_surface_variant" }),
    }))
    return
  end

  local children = {}
  if #rows == 0 then
    table.insert(children, ui.label({ text = "Nothing here", color = "on_surface_variant" }))
  else
    revealCursor()
    for index = windowStart, math.min(#rows, windowStart + windowRows() - 1) do
      local row = rows[index]
      -- One rule where the open level's own hits give way to deeper ones. A
      -- filled row rather than ui.separator, which lays out to nothing inside
      -- ui.scroll — this is the mechanism that paints the cursor highlight.
      if row.deeper and index > windowStart and not rows[index - 1].deeper then
        table.insert(children, ui.row({
          key = "deeper-rule",
          padding = 0,
          fill = "on_surface/0.35",
        }, { ui.spacer({ height = 1 }) }))
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
      placeholder = "Search the menu…",
      focus = true,
      onChange = "onQueryChanged",
      onSubmit = "onQuerySubmitted",
    }),

    ui.scroll({ flexGrow = 1, gap = 2, align = "stretch" }, children),
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
  cursor = 1

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

function activate()
  interacted = true

  local row = rows[cursor]
  if not row then
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
  -- Leaving search mode: the row was found across the tree, so the level it
  -- opens is wherever it actually lives.
  query = ""
  searchRevision += 1
  enter(destination)
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
  cursor = 1
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
  pendingContext = context
  interacted = false
  -- Provider rows belong to the previous open, whichever path draws this one.
  providerFor = nil
  providerRows = {}

  -- Paint from what the last open left behind, so the panel is on screen and
  -- usable on the first frame instead of sitting on "Loading the menu…" for as
  -- long as the guards take. refreshState() corrects it in place below.
  if canPaintFromRetained(context) then
    openAt(context)
  elseif not menu then
    render()
  end

  refreshState(function()
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
  end)
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
  if not pressed or not menu then
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
    if not back() then
      panel.close()
    end
  end
end

function onCloseClicked()
  panel.close()
end

-- `monarch menu <route>` reaches the panel through this when it is already
-- open, so a second keybind press re-routes instead of doing nothing.
function onIpc(event, payload)
  if event == "open" then
    openAt(payload)
  end
end
