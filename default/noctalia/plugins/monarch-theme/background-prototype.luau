--!nonstrict

-- Three background-selector variants, switched with Ctrl+Left/Right.

local HOME = noctalia.getenv("HOME") or ""
local ROOT = HOME .. "/.config/monarch/backgrounds/current"
local all = {}
local rows = {}
local selected = 1
local query = ""
local variant = 1
local status = ""
local loading = true
local render
local names = { "A — Gallery", "B — Spotlight", "C — Carousel" }

local function basename(path)
  return path:match("([^/]+)$") or path
end

local function isImage(path)
  local lower = path:lower()
  return lower:match("%.jpg$") or lower:match("%.jpeg$") or lower:match("%.png$")
    or lower:match("%.gif$") or lower:match("%.bmp$") or lower:match("%.webp$")
end

local function filter()
  rows = {}
  for _, path in ipairs(all) do
    if query == "" or noctalia.fuzzyScore(query, basename(path)) then
      table.insert(rows, path)
    end
  end
  selected = math.max(1, math.min(selected, #rows))
end

local function load()
  loading = true
  local command = "/usr/bin/find -L '" .. ROOT .. "' -maxdepth 1 -type f -print"
  noctalia.runAsync(command, function(result)
    loading = false
    all = {}
    if result and result.exitCode == 0 then
      for path in (result.stdout or ""):gmatch("[^\n]+") do
        if isImage(path) then table.insert(all, path) end
      end
    end
    table.sort(all)
    filter()
    render()
  end)
end

local function choose(index)
  if #rows == 0 then return end
  selected = math.max(1, math.min(index, #rows))
  status = ""
  render()
end

local function thumb(path, index, width, height)
  local active = index == selected
  return ui.column({
    width = width,
    gap = 5,
    padding = 5,
    radius = 9,
    fill = active and "primary/0.16" or "surface_container/0.45",
    onClick = function() choose(index) end,
  }, {
    ui.image({ path = path, width = width - 10, height = height, fit = "cover", radius = 7, border = active and "primary" or "outline", borderWidth = active and 2 or 1 }),
    ui.label({ text = basename(path), fontSize = 10, color = active and "primary" or "on_surface_variant", elide = "right" }),
  })
end

local function gallery()
  local children = {}
  local start = math.floor((selected - 1) / 9) * 9 + 1
  for row = 0, 2 do
    local cells = {}
    for column = 1, 3 do
      local index = start + row * 3 + column - 1
      if rows[index] then table.insert(cells, thumb(rows[index], index, 268, 105))
      else table.insert(cells, ui.spacer({ width = 268 })) end
    end
    table.insert(children, ui.row({ gap = 10 }, cells))
  end
  return ui.column({ gap = 8 }, children)
end

local function spotlight()
  local path = rows[selected]
  local rail = {}
  local start = math.max(1, math.min(selected - 1, math.max(1, #rows - 2)))
  for index = start, math.min(start + 2, #rows) do
    table.insert(rail, thumb(rows[index], index, 205, 105))
  end
  return ui.row({ gap = 16, flexGrow = 1 }, {
    ui.column({ flexGrow = 1, gap = 10 }, {
      ui.image({ path = path, height = 370, fit = "cover", radius = 12, border = "primary", borderWidth = 2 }),
      ui.label({ text = basename(path), fontSize = 16, fontWeight = "bold" }),
    }),
    ui.column({ width = 205, gap = 8 }, rail),
  })
end

local function carousel()
  local path = rows[selected]
  local strip = {}
  local start = math.max(1, math.min(selected - 2, math.max(1, #rows - 4)))
  for index = start, math.min(start + 4, #rows) do
    table.insert(strip, thumb(rows[index], index, 155, 72))
  end
  return ui.column({ gap = 12, align = "center" }, {
    ui.image({ path = path, width = 820, height = 340, fit = "cover", radius = 12, border = "primary", borderWidth = 2 }),
    ui.label({ text = basename(path), fontSize = 16, fontWeight = "bold" }),
    ui.row({ gap = 8 }, strip),
  })
end

local function content()
  if loading then return ui.label({ text = "Loading backgrounds…", color = "on_surface_variant" }) end
  if #rows == 0 then return ui.label({ text = "No matching background", color = "on_surface_variant" }) end
  if variant == 1 then return gallery()
  elseif variant == 2 then return spotlight()
  else return carousel() end
end

local function switch(next)
  variant = ((variant - 1 + next) % #names) + 1
  status = ""
  render()
end

function render()
  panel.render(ui.column({ flexGrow = 1, gap = 12, padding = 18 }, {
    ui.row({ align = "center", gap = 12 }, {
      ui.column({ flexGrow = 1, gap = 2 }, {
        ui.label({ text = "Choose a background", fontSize = 18, fontWeight = "bold" }),
        ui.label({ text = #rows .. " images from the active theme", fontSize = 11, color = "on_surface_variant" }),
      }),
      ui.button({ glyph = "close", onClick = "onCloseClicked" }),
    }),
    ui.input({ key = "background-search", placeholder = "Search backgrounds…", focus = true, onChange = "onQueryChanged", onSubmit = "onQuerySubmitted" }),
    content(),
    ui.row({ align = "center", gap = 10 }, {
      ui.label({ text = status ~= "" and status or "Arrows Navigate · Enter Preview", fontSize = 11, color = "on_surface_variant", flexGrow = 1 }),
      ui.button({ glyph = "chevron-left", onClick = "onPreviousVariant" }),
      ui.label({ text = names[variant], fontSize = 11, fontWeight = "bold", width = 110, align = "center" }),
      ui.button({ glyph = "chevron-right", onClick = "onNextVariant" }),
    }),
  }))
end

function onOpen()
  query = ""
  selected = 1
  variant = 1
  status = ""
  load()
end

function onCloseClicked() panel.close() end
function onPreviousVariant() switch(-1) end
function onNextVariant() switch(1) end

function onQueryChanged(value)
  query = value or ""
  selected = 1
  filter()
  render()
end

function onQuerySubmitted(_value)
  if rows[selected] then status = "Would apply " .. basename(rows[selected]); render() end
end

function onKey(chord, pressed)
  if not pressed then return end
  if chord == "escape" then panel.close()
  elseif chord == "ctrl+left" then switch(-1)
  elseif chord == "ctrl+right" then switch(1)
  elseif chord == "home" then choose(1)
  elseif chord == "end" then choose(#rows)
  elseif chord == "return" then onQuerySubmitted("")
  elseif variant == 1 and chord == "left" then choose(selected - 1)
  elseif variant == 1 and chord == "right" then choose(selected + 1)
  elseif variant == 1 and chord == "up" then choose(selected - 3)
  elseif variant == 1 and chord == "down" then choose(selected + 3)
  elseif variant == 2 and chord == "up" then choose(selected - 1)
  elseif variant == 2 and chord == "down" then choose(selected + 1)
  elseif variant == 3 and chord == "left" then choose(selected - 1)
  elseif variant == 3 and chord == "right" then choose(selected + 1)
  end
end
