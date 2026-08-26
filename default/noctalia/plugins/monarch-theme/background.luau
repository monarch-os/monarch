--!nonstrict

local HOME = noctalia.getenv("HOME") or ""
local BIN = HOME .. "/.local/share/monarch/bin"
local LIST = BIN .. "/monarch-theme-background-list"

local backgrounds = {}
local rows = {}
local selected = 1
local windowStart = 1
local query = ""
local loading = true
local applying = false
local importing = false
local removing = false
local removeArmed = ""
local status = ""
local render
local WINDOW_ROWS = 3
local TRACK_HEIGHT = 390

local function quote(text)
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function reveal()
  if selected < windowStart then
    windowStart = selected
  elseif selected > windowStart + WINDOW_ROWS - 1 then
    windowStart = selected - WINDOW_ROWS + 1
  end
  windowStart = math.max(1, math.min(windowStart, math.max(1, #rows - WINDOW_ROWS + 1)))
end

local function filterRows()
  rows = {}
  for _, background in ipairs(backgrounds) do
    if query == "" or noctalia.fuzzyScore(query, background.name) then
      table.insert(rows, background)
    end
  end
  selected = math.max(1, math.min(selected, #rows))
  windowStart = 1
  reveal()
end

local function parse(text)
  local parsed = {}
  for line in text:gmatch("[^\n]+") do
    local current, name, path, thumbnail, removable = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
    if name and path ~= "" and thumbnail ~= "" then
      table.insert(parsed, { current = current == "true", name = name, path = path, thumbnail = thumbnail, removable = removable == "true" })
    end
  end
  return parsed
end

local function load()
  loading = true
  noctalia.runAsync(LIST, function(result)
    loading = false
    if not result or result.exitCode ~= 0 then
      status = "Could not load backgrounds"
      backgrounds = {}
      render()
      return
    end
    backgrounds = parse(result.stdout or "")
    filterRows()
    for index, background in ipairs(rows) do
      if background.current then selected = index end
    end
    reveal()
    render()
  end)
end

local function choose(index)
  selected = index
  removeArmed = ""
  reveal()
  status = ""
  render()
end

local function apply()
  local background = rows[selected]
  if applying or importing or removing or not background then return end
  applying = true
  status = "Applying " .. background.name .. "…"
  render()
  noctalia.runAsync("/usr/bin/noctalia msg wallpaper-set " .. quote(background.path), function(result)
    applying = false
    if not result or result.exitCode ~= 0 then
      status = "Could not apply " .. background.name
      render()
      return
    end
    for _, item in ipairs(backgrounds) do item.current = item.path == background.path end
    status = background.name .. " applied"
    render()
  end)
end

local function importBackground()
  if importing or applying or removing then return end
  importing = true
  panel.close()
  noctalia.runAsync(BIN .. "/monarch-theme-background-import", function(result)
    importing = false
    if not result or result.exitCode ~= 0 then
      status = "Could not import background"
    elseif not (result.stdout or ""):match("([^\n]+)") then
      status = ""
    end
    noctalia.runAsync("/usr/bin/noctalia msg panel-open monarch/theme:background")
  end)
end

local function removeBackground()
  local background = rows[selected]
  if removing or applying or importing or not background or not background.removable then return end
  if removeArmed ~= background.path then
    removeArmed = background.path
    status = "Press Remove again to delete " .. background.name
    render()
    return
  end
  removing = true
  status = "Removing " .. background.name .. "…"
  render()
  noctalia.runAsync(BIN .. "/monarch-theme-background-remove " .. quote(background.path), function(result)
    removing = false
    removeArmed = ""
    if not result or result.exitCode ~= 0 then
      status = "Could not remove " .. background.name
      render()
      return
    end
    status = background.name .. " removed"
    load()
  end)
end

local function thumbnailList()
  local children = {}
  local last = math.min(windowStart + WINDOW_ROWS - 1, #rows)
  for index = windowStart, last do
    local background = rows[index]
    local active = index == selected
    table.insert(children, ui.column({
      key = background.path,
      width = 220,
      gap = 4,
      padding = 5,
      radius = 9,
      fill = active and "primary/0.16" or "primary/0",
      onClick = function() choose(index) end,
    }, {
      ui.image({ path = background.thumbnail, width = 210, height = 96, fit = "cover", radius = 7, border = active and "primary" or "outline", borderWidth = active and 2 or 1 }),
      ui.row({ align = "center", gap = 5 }, {
        ui.label({ text = background.name, fontSize = 10, color = active and "primary" or "on_surface_variant", flexGrow = 1 }),
        background.current and ui.label({ text = "✓", color = "primary" }) or ui.spacer({ width = 0 }),
      }),
    }))
  end

  local total = #rows
  local thumbHeight = if total <= WINDOW_ROWS then TRACK_HEIGHT
    else math.max(32, math.floor(TRACK_HEIGHT * WINDOW_ROWS / total))
  local travel = TRACK_HEIGHT - thumbHeight
  local top = if total <= WINDOW_ROWS then 0
    else math.floor(travel * (windowStart - 1) / (total - WINDOW_ROWS))
  local bottom = TRACK_HEIGHT - thumbHeight - top

  return ui.row({ width = 232, gap = 7, align = "start" }, {
    ui.column({ width = 220, gap = 5 }, children),
    ui.column({ width = 5, height = TRACK_HEIGHT, gap = 0 }, {
      ui.box({ width = 5, height = top, fill = "outline/0.16", radius = 3 }),
      ui.box({ width = 5, height = thumbHeight, fill = "primary/0.65", radius = 3 }),
      ui.box({ width = 5, height = bottom, fill = "outline/0.16", radius = 3 }),
    }),
  })
end

local function content()
  if loading then
    return ui.label({ text = "Loading backgrounds…", color = "on_surface_variant" })
  end
  local background = rows[selected]
  if not background then
    return ui.label({ text = status ~= "" and status or "No matching background", color = status:match("Could not") and "error" or "on_surface_variant" })
  end
  return ui.row({ flexGrow = 1, gap = 18 }, {
    thumbnailList(),
    ui.column({ flexGrow = 1, gap = 12 }, {
      ui.image({ path = background.thumbnail, height = 375, fit = "cover", radius = 12, border = "primary", borderWidth = 2 }),
      ui.row({ align = "center", gap = 12 }, {
        ui.column({ flexGrow = 1, gap = 3 }, {
          ui.label({ text = background.name, fontSize = 18, fontWeight = "bold" }),
          ui.label({ text = background.current and "Current background" or "Preview from the active theme", fontSize = 11, color = "on_surface_variant" }),
        }),
        background.removable and ui.button({ text = removeArmed == background.path and "Confirm remove" or "Remove", variant = "secondary", enabled = not applying and not importing and not removing, onClick = "onRemoveClicked" }) or ui.spacer({ width = 0 }),
        ui.button({ text = applying and "Applying…" or "Use background", variant = "primary", enabled = not applying and not importing and not removing and not background.current, onClick = apply }),
      }),
    }),
  })
end

function render()
  panel.render(ui.column({ flexGrow = 1, gap = 12, padding = 18 }, {
    ui.row({ align = "center", gap = 12 }, {
      ui.column({ flexGrow = 1, gap = 2 }, {
        ui.label({ text = "Choose a background", fontSize = 18, fontWeight = "bold" }),
        ui.label({ text = #rows .. " images from the active theme", fontSize = 11, color = "on_surface_variant" }),
      }),
      ui.button({ text = importing and "Importing…" or "Import", glyph = "file-import", enabled = not importing and not applying and not removing, onClick = "onImportClicked" }),
      ui.button({ glyph = "close", onClick = "onCloseClicked" }),
    }),
    ui.input({ key = "background-search", placeholder = "Search backgrounds…", focus = true, onChange = "onQueryChanged", onSubmit = "onQuerySubmitted" }),
    content(),
    ui.label({ text = status ~= "" and status or "↑↓ Select · Enter Apply · Ctrl+I Import · Delete Remove", fontSize = 11, color = status:match("Could not") and "error" or "on_surface_variant" }),
  }))
end

function onOpen()
  status = ""
  query = ""
  load()
end

function onCloseClicked() panel.close() end
function onImportClicked() importBackground() end
function onRemoveClicked() removeBackground() end

function onQueryChanged(value)
  query = value or ""
  selected = 1
  filterRows()
  render()
end

function onQuerySubmitted(_value)
  apply()
end

function onKey(chord, pressed)
  if not pressed then return end
  if chord == "escape" then panel.close()
  elseif chord == "ctrl+i" then importBackground()
  elseif chord == "delete" then removeBackground()
  elseif #rows == 0 then return
  elseif chord == "down" or chord == "ctrl+j" then choose(if selected == #rows then 1 else selected + 1)
  elseif chord == "up" or chord == "ctrl+k" then choose(if selected == 1 then #rows else selected - 1)
  elseif chord == "home" then choose(1)
  elseif chord == "end" then choose(#rows)
  elseif chord == "return" then apply()
  end
end
