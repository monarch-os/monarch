--!nonstrict

local HOME = noctalia.getenv("HOME") or ""
local BIN = HOME .. "/.local/share/monarch/bin"
local themes = {}
local rows = {}
local selected = 1
local windowStart = 1
local query = ""
local loading = true
local status = ""
local render
local WINDOW_ROWS = 9
local TRACK_HEIGHT = 351

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
  for _, theme in ipairs(themes) do
    if query == "" or noctalia.fuzzyScore(query, theme.name) then
      table.insert(rows, theme)
    end
  end
  selected = math.max(1, math.min(selected, #rows))
  windowStart = 1
  reveal()
end

local function quote(text)
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function parse(text)
  local rows = {}
  for line in text:gmatch("[^\n]+") do
    local current, name, slug, preview = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
    if name and preview ~= "" then
      table.insert(rows, { current = current == "true", name = name, slug = slug, preview = preview })
    end
  end
  return rows
end

local function load()
  loading = true
  noctalia.runAsync(BIN .. "/monarch-unlock-list", function(result)
    loading = false
    if not result or result.exitCode ~= 0 then
      status = "Could not load unlock themes"
      themes = {}
      render()
      return
    end
    themes = parse(result.stdout or "")
    filterRows()
    for index, theme in ipairs(rows) do
      if theme.current then selected = index end
    end
    reveal()
    render()
  end)
end

local function choose(index)
  selected = index
  reveal()
  status = ""
  render()
end

local function apply()
  local theme = rows[selected]
  if not theme then return end
  local action = if theme.slug == "default" then BIN .. "/monarch-plymouth-reset"
    else BIN .. "/monarch-plymouth-apply " .. quote(theme.name)
  local command = BIN .. "/monarch-launch-floating-terminal-with-presentation " .. quote(action)
  noctalia.runAsync(command)
  panel.close()
end

local function listView()
  local children = {}
  local last = math.min(windowStart + WINDOW_ROWS - 1, #rows)
  for index = windowStart, last do
    local theme = rows[index]
    local active = index == selected
    table.insert(children, ui.row({
      key = theme.slug,
      align = "center",
      gap = 10,
      padding = 10,
      radius = 8,
      fill = active and "primary/0.14" or "primary/0",
      onClick = function() choose(index) end,
    }, {
      ui.label({ text = theme.name, color = active and "primary" or "on_surface", flexGrow = 1 }),
      theme.current and ui.label({ text = "✓", color = "primary" }) or ui.spacer({ width = 0 }),
    }))
  end
  local total = #rows
  local thumbHeight = if total <= WINDOW_ROWS then TRACK_HEIGHT
    else math.max(32, math.floor(TRACK_HEIGHT * WINDOW_ROWS / total))
  local travel = TRACK_HEIGHT - thumbHeight
  local top = if total <= WINDOW_ROWS then 0
    else math.floor(travel * (windowStart - 1) / (total - WINDOW_ROWS))
  local bottom = TRACK_HEIGHT - thumbHeight - top

  return ui.row({ width = 217, gap = 7, align = "start" }, {
    ui.column({ width = 205, gap = 3 }, children),
    ui.column({ width = 5, height = TRACK_HEIGHT, gap = 0 }, {
      ui.box({ width = 5, height = top, fill = "outline/0.16", radius = 3 }),
      ui.box({ width = 5, height = thumbHeight, fill = "primary/0.65", radius = 3 }),
      ui.box({ width = 5, height = bottom, fill = "outline/0.16", radius = 3 }),
    }),
  })
end

local function content()
  if loading then
    return ui.label({ text = "Loading unlock themes…", color = "on_surface_variant" })
  end
  local theme = rows[selected]
  if not theme then
    return ui.label({ text = status ~= "" and status or "No unlock preview found", color = "error" })
  end
  return ui.row({ flexGrow = 1, gap = 20 }, {
    listView(),
    ui.column({ flexGrow = 1, gap = 12 }, {
      ui.image({ path = theme.preview, height = 355, fit = "cover", radius = 12, border = "primary", borderWidth = 2 }),
      ui.row({ align = "center", gap = 12 }, {
        ui.column({ flexGrow = 1, gap = 3 }, {
          ui.label({ text = theme.name, fontSize = 20, fontWeight = "bold" }),
          ui.label({ text = theme.current and "Current Plymouth and SDDM theme" or "Login and boot preview", fontSize = 12, color = "on_surface_variant" }),
        }),
        ui.button({ text = "Use unlock theme", variant = "primary", enabled = not theme.current, onClick = apply }),
      }),
    }),
  })
end

function render()
  panel.render(ui.column({ flexGrow = 1, gap = 14, padding = 18 }, {
    ui.row({ align = "center", gap = 12 }, {
      ui.column({ flexGrow = 1, gap = 2 }, {
        ui.label({ text = "Choose an unlock theme", fontSize = 18, fontWeight = "bold" }),
        ui.label({ text = "Apply one appearance to both SDDM and Plymouth", fontSize = 11, color = "on_surface_variant" }),
      }),
      ui.button({ glyph = "close", onClick = "onCloseClicked" }),
    }),
    ui.separator({}),
    ui.input({
      key = "unlock-search",
      placeholder = "Search unlock themes…",
      focus = true,
      onChange = "onQueryChanged",
      onSubmit = "onQuerySubmitted",
    }),
    content(),
    ui.label({ text = status ~= "" and status or "↑↓ Select · Enter Apply", fontSize = 11, color = "on_surface_variant" }),
  }))
end

function onOpen()
  status = ""
  query = ""
  load()
end

function onCloseClicked() panel.close() end

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
  if not pressed or #rows == 0 then return end
  if chord == "escape" then panel.close()
  elseif chord == "down" or chord == "ctrl+j" then choose(if selected == #rows then 1 else selected + 1)
  elseif chord == "up" or chord == "ctrl+k" then choose(if selected == 1 then #rows else selected - 1)
  elseif chord == "home" then choose(1)
  elseif chord == "end" then choose(#rows)
  elseif chord == "return" then apply()
  end
end
