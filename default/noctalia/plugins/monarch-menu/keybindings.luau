--!nonstrict

local MONARCH_ROOT = noctalia.getenv("MONARCH_PATH") or "/usr/share/monarch"

local bindings = {}
local rows = {}
local query = ""
local loading = true
local status = ""
local title = "Keybindings"
local command = MONARCH_ROOT .. "/bin/monarch-menu-keybindings --json"
local render

local function shellQuote(text)
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function configure(context)
  local payload = type(context) == "string" and noctalia.json.decode(context) or nil
  if type(payload) == "table" and payload.kind == "herdr" then
    title = "Herdr keybindings"
    command = MONARCH_ROOT .. "/bin/monarch-menu-herdr-keybindings --json"
    if type(payload.config) == "string" and payload.config ~= "" then
      command = command .. " --config " .. shellQuote(payload.config)
    end
    return
  end

  title = "Keybindings"
  command = MONARCH_ROOT .. "/bin/monarch-menu-keybindings --json"
end

local function filterRows()
  rows = {}
  for _, binding in bindings do
    if query == "" or noctalia.fuzzyScore(query, binding.searchText) then
      table.insert(rows, binding)
    end
  end
end

local function loadBindings()
  loading = true
  status = ""
  noctalia.runAsync(command, function(result)
    loading = false
    if not result or result.exitCode ~= 0 then
      status = "Could not load keybindings"
      bindings = {}
      rows = {}
      render()
      return
    end

    local decoded = noctalia.json.decode(result.stdout or "")
    if type(decoded) ~= "table" then
      status = "The keybindings did not parse"
      bindings = {}
      rows = {}
      render()
      return
    end

    bindings = decoded
    filterRows()
    render()
  end)
end

local function headerText()
  if loading then return title end
  local noun = if query ~= "" then
      (if #rows == 1 then "result" else "results")
    else (if #rows == 1 then "shortcut" else "shortcuts")
  return title .. "  ·  " .. tostring(#rows) .. " " .. noun
end

local function content()
  if loading then
    return { ui.label({ text = "Loading keybindings…", color = "on_surface_variant" }) }
  end
  if #rows == 0 then
    return { ui.label({
      text = status ~= "" and status or "No keybindings found",
      color = status ~= "" and "error" or "on_surface_variant",
    }) }
  end

  local children = {}
  for _, binding in rows do
    table.insert(children, ui.row({
      key = binding.shortcut .. ":" .. binding.label,
      align = "center",
      gap = 10,
      padding = 8,
      radius = 8,
      fill = "primary/0",
    }, {
      ui.label({ text = "", width = 22, color = "on_surface" }),
      ui.column({ flexGrow = 1, gap = 1 }, {
        ui.label({ text = binding.label, color = "on_surface", maxLines = 1 }),
        ui.label({
          text = binding.shortcut:gsub(" / ", "  ·  "),
          fontSize = 11,
          color = "on_surface/0.55",
          maxLines = 1,
        }),
      }),
    }))
  end
  return children
end

function render()
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
      key = "keybindings-search",
      placeholder = "Search " .. title:lower() .. "…",
      focus = true,
      onChange = "onQueryChanged",
    }),
    ui.scroll({ flexGrow = 1, gap = 2, align = "stretch" }, content()),
    ui.row({ align = "center", gap = 14 }, {
      ui.label({ text = "Scroll to browse", fontSize = 11, color = "on_surface/0.55" }),
      ui.label({ text = "Type to filter", fontSize = 11, color = "on_surface/0.55" }),
      ui.label({ text = "Esc Close", fontSize = 11, color = "on_surface/0.55" }),
    }),
  }))
end

function onOpen(context)
  configure(context)
  query = ""
  loadBindings()
  render()
end

function onQueryChanged(value)
  query = value or ""
  filterRows()
  render()
end

function onKey(chord, pressed)
  if not pressed then return end
  if chord == "escape" then
    panel.close()
  end
end

function onCloseClicked()
  panel.close()
end
