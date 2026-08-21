--!nonstrict
-- The display panel, laid out after quattro's omarchy.monitor.
--
-- Presentation and sequencing only: everything it knows comes from Monarch
-- commands printing tab-separated fields, so the logic that talks to niri stays
-- in bash where it can be tested without a compositor.

local shared = require("./shared.luau")

local LIST_CMD = shared.bin("monarch-display-list")
local SCALE_CMD = shared.bin("monarch-display-scale")
local TOGGLE_CMD = shared.bin("monarch-display-toggle")
local TEXT_CMD = shared.bin("monarch-display-text-size")
local BRIGHT_CMD = shared.bin("monarch-display-brightness")
local FOCUS_CMD = shared.bin("monarch-launch-or-focus")

-- nwg-displays does placement, speaks niri, and shares the file Monarch writes
-- into. Offered only when it is there: the package is removable like any other.
local ARRANGE = noctalia.commandExists("nwg-displays")

-- What Mod+Ctrl+D cycles through, cleaned against the mode before it is offered.
local SCALES = { 1, 1.25, 1.6, 2, 3, 4 }
-- Wayland counts scale in 120ths of a pixel.
local SCALE_UNIT = 120
local TEXT_STEP = 5
local TEXT_MIN = 75
local TEXT_MAX = 175
-- Noctalia clamps to its own minimum anyway; this floor only keeps the slider
-- from offering a screen too dark to turn back up.
local BRIGHT_STEP = 5
local BRIGHT_MIN = 5
-- Hardware keys change brightness behind this panel's back, so it is re-read
-- while open. Cheap: sysfs, or a cache the command keeps for the bus.
local BRIGHT_POLL = 2

local outputs = {}
-- As read, what the sliders show while a drag leads it, and what a busy screen
-- still owes.
local brightness = {}
local liveBrightness = {}
local sending = {}
local queuedBrightness = {}
local brightTicks = 0
local textPercent = 100
local loaded = false
-- The action in flight ("" when idle). One at a time: these all reload niri's
-- config, and a second write landing mid-reload is not worth allowing for.
local busy = ""
local errorText = ""

-- Every text-size step rewrites two files and pokes gsettings, far slower than
-- the slider moves: a drag parks its value here and the tick commits it.
local pendingPercent = nil
local settleTicks = 0
local SETTLE = 1

-- A read started before the last click must not land on top of newer state.
local generation = 0

local render

local function gcd(a: number, b: number): number
  while b ~= 0 do
    a, b = b, a % b
  end
  return a
end

-- A scale whose 120ths divide gcd(width, height) in the same units leaves both
-- logical dimensions whole; anything else is the compositor rounding behind your
-- back. Hence 1.33x and 3.13x rather than the round numbers asked for.
local function cleanScale(requested: number, width: number, height: number): number?
  if requested <= 0 or width <= 0 or height <= 0 then
    return nil
  end

  local divisor = gcd(width * SCALE_UNIT, height * SCALE_UNIT)
  local units = math.max(1, math.floor(requested * SCALE_UNIT + 0.5))
  if units > divisor then
    units = divisor
  end
  while divisor % units ~= 0 do
    units += 1
  end

  return units / SCALE_UNIT
end

local function formatScale(value: number): string
  local rounded = math.floor(value * 100 + 0.5) / 100
  if rounded == math.floor(rounded) then
    return tostring(math.floor(rounded))
  end
  return (string.format("%.2f", rounded):gsub("0$", ""))
end

-- "1515x884@60" — the pixel mode, which is what the cleaning is against.
local function modePixels(mode: string): (number, number)
  local width, height = mode:match("^(%d+)x(%d+)")
  return tonumber(width) or 0, tonumber(height) or 0
end

local function parseOutputs(text: string)
  local rows = {}

  for line in text:gmatch("[^\n]+") do
    -- Description last, being the only field that may contain a tab.
    local name, state, scale, mode, focused, description =
      line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
    if name and name ~= "" then
      table.insert(rows, {
        name = name,
        on = state == "on",
        scale = scale,
        mode = mode,
        focused = focused == "focused",
        description = description,
      })
    end
  end

  return rows
end

-- name<TAB>percent<TAB>backend, one line per screen something can dim. A screen
-- absent from it gets no slider.
local function parseBrightness(text: string)
  local rows = {}

  for line in text:gmatch("[^\n]+") do
    local name, percent = line:match("^([^\t]*)\t(%d+)\t")
    if name and name ~= "" then
      rows[name] = tonumber(percent)
    end
  end

  return rows
end

local function readBrightness()
  noctalia.runAsync(BRIGHT_CMD .. " --list", function(result)
    if not result or result.exitCode ~= 0 then
      return
    end
    brightness = parseBrightness(result.stdout or "")
    -- How a brightness key pressed with the panel open lands here.
    for name in pairs(liveBrightness) do
      if not sending[name] and queuedBrightness[name] == nil then
        liveBrightness[name] = nil
      end
    end
    render()
  end)
end

local sendBrightness

-- Not runAction: taking the panel busy and re-reading niri is the right ceremony
-- for a scale and far too much for a slider. One command per screen at a time,
-- and the last value asked for while it was busy goes out behind it.
function sendBrightness(name: string, percent: number)
  sending[name] = true

  noctalia.runAsync(BRIGHT_CMD .. " " .. shared.shellQuote(name) .. " " .. percent, function(result)
    sending[name] = nil

    if not result or result.exitCode ~= 0 then
      errorText = shared.errorFrom(result, "Could not set the brightness on " .. name)
      liveBrightness[name] = nil
      queuedBrightness[name] = nil
      render()
      return
    end

    -- Nothing else clears it on this path.
    if errorText ~= "" then
      errorText = ""
      render()
    end

    local pending = queuedBrightness[name]
    if pending ~= nil then
      queuedBrightness[name] = nil
      sendBrightness(name, pending)
    end
  end)
end

local function focusedOutput()
  for _, output in ipairs(outputs) do
    if output.focused then
      return output
    end
  end
  -- Nothing focused happens mid-transition; the first lit screen beats no row.
  for _, output in ipairs(outputs) do
    if output.on then
      return output
    end
  end
  return nil
end

local function refresh()
  generation += 1
  local ticket = generation

  noctalia.runAsync(LIST_CMD, function(result)
    if ticket ~= generation then return end
    loaded = true
    outputs = (result and result.exitCode == 0) and parseOutputs(result.stdout or "") or {}
    render()
  end)

  readBrightness()

  noctalia.runAsync(TEXT_CMD .. " --current", function(result)
    if ticket ~= generation then return end
    if result and result.exitCode == 0 and pendingPercent == nil then
      textPercent = tonumber((result.stdout or ""):match("%d+")) or textPercent
    end
    render()
  end)
end

-- Keep whatever the command said on stderr, and re-read rather than guess at the
-- new state. The refusal to blank the last lit screen speaks through this path.
local function runAction(token: string, command: string, fallback: string)
  if busy ~= "" then
    return
  end

  busy = token
  errorText = ""
  render()

  noctalia.runAsync(command, function(result)
    busy = ""
    if not result or result.exitCode ~= 0 then
      errorText = shared.errorFrom(result, fallback)
    end
    refresh()
  end)
end

-- Keyed, like everything else here: the tree diff matches by position when it
-- cannot match by key, and a row landing where a card used to be comes out
-- wearing its border.
local function sectionHeader(key: string, text: string, value: string?): any
  return ui.row({ key = key, align = "center", gap = 8 }, {
    ui.label({ text = text, fontSize = 11, fontWeight = "medium", color = "on_surface_variant", flexGrow = 1 }),
    ui.label({ text = value or "", fontSize = 11, fontWeight = "medium", color = "on_surface" }),
  })
end

local function brightnessOf(name: string): number?
  return liveBrightness[name] or brightness[name]
end

-- A slider each rather than quattro's focused screen alone: one line more per
-- screen, and no trip through focus to reach the other monitor.
local function brightnessSection(): { any }
  local lit = {}
  for _, output in ipairs(outputs) do
    if output.on and brightness[output.name] ~= nil then
      table.insert(lit, output)
    end
  end

  if #lit == 0 then
    return {}
  end

  local single = #lit == 1
  local nodes = {
    sectionHeader("head:brightness", "BRIGHTNESS", single and (brightnessOf(lit[1].name) .. "%") or ""),
  }

  for _, output in ipairs(lit) do
    local name = output.name
    if not single then
      table.insert(nodes, sectionHeader("head:brightness:" .. name, name, brightnessOf(name) .. "%"))
    end

    table.insert(nodes, ui.slider({
      key = "brightness:" .. name,
      min = BRIGHT_MIN,
      max = 100,
      step = BRIGHT_STEP,
      value = brightnessOf(name),
      onChange = function(value)
        local percent = tonumber(value)
        if not percent then
          return
        end

        percent = math.max(BRIGHT_MIN, math.min(100, math.floor(percent / BRIGHT_STEP + 0.5) * BRIGHT_STEP))
        if percent == brightnessOf(name) then
          return
        end

        -- Live, and not on release: this one is set by looking at the screen.
        liveBrightness[name] = percent
        render()

        if sending[name] then
          queuedBrightness[name] = percent
        else
          sendBrightness(name, percent)
        end
      end,
    }))
  end

  table.insert(nodes, ui.separator({ key = "sep:brightness" }))
  return nodes
end

local function textSizeSection(): { any }
  return {
    sectionHeader("head:text", "TEXT SIZE", (pendingPercent or textPercent) .. "%"),
    ui.slider({
      key = "slider:text",
      min = TEXT_MIN,
      max = TEXT_MAX,
      step = TEXT_STEP,
      value = pendingPercent or textPercent,
      enabled = busy == "",
      onChange = function(value)
        local percent = tonumber(value)
        if not percent then
          return
        end
        pendingPercent = math.max(TEXT_MIN, math.min(TEXT_MAX, math.floor(percent / TEXT_STEP + 0.5) * TEXT_STEP))
        settleTicks = 0
        render()
      end,
    }),
    ui.label({
      text = "The bar, the panels, GTK apps and the terminal, together.",
      fontSize = 11,
      color = "on_surface_variant",
    }),
  }
end

-- Pills and not a dropdown: the choice is short and worth reading at a glance.
local function scaleSection(): { any }
  local focused = focusedOutput()
  if not focused or not focused.on then
    return {}
  end

  local width, height = modePixels(focused.mode)
  local current = tonumber(focused.scale)
  local choices = {}
  local seen = {}

  for _, preset in ipairs(SCALES) do
    local clean = cleanScale(preset, width, height)
    -- 1366x768 keeps only 1x and 2x: the row shrinks rather than offer a value
    -- the compositor would have to round.
    if clean and not seen[clean] then
      seen[clean] = true
      table.insert(choices, clean)
    end
  end

  -- Or a scale set by hand could never be picked back from here.
  if current and not seen[current] then
    table.insert(choices, current)
    table.sort(choices)
  end

  -- One value is not a choice, and a lone stretched pill claiming to be a picker
  -- is worse than saying nothing.
  if #choices < 2 then
    return {}
  end

  local pills = {}
  for _, value in ipairs(choices) do
    local active = current ~= nil and value == current
    table.insert(pills, ui.button({
      -- Adding the arrange button below once left a pill wearing its glyph.
      key = "scale:" .. formatScale(value),
      text = formatScale(value) .. "x",
      variant = active and "primary" or "outline",
      controlSize = "sm",
      -- Content-sized pills make 1x a third the width of 1.25x.
      flexGrow = 1,
      enabled = busy == "" and not active,
      onClick = function()
        runAction("scale",
          SCALE_CMD .. " " .. shared.shellQuote(focused.name) .. " " .. shared.shellQuote(formatScale(value)),
          "Could not scale " .. focused.name)
      end,
    }))
  end

  return {
    ui.separator({ key = "sep:scale" }),
    sectionHeader("head:scale", "SCALE", focused.name),
    ui.row({ key = "row:scale", gap = 6, align = "center" }, pills),
  }
end

-- A bordered row and not ui.box: a box paints only where it has a width and a
-- height of its own, and a card is as wide as whatever is in it.
local function litCount(): number
  local lit = 0
  for _, output in ipairs(outputs) do
    if output.on then
      lit += 1
    end
  end
  return lit
end

local function outputRow(output): any
  local children = {
    ui.glyph({
      name = output.on and "device-desktop" or "device-desktop-off",
      size = 18,
      color = output.on and "on_surface" or "on_surface_variant",
    }),
    ui.column({ gap = 2, flexGrow = 1 }, {
      ui.label({
        text = output.name,
        fontSize = 13,
        fontWeight = output.focused and "medium" or "regular",
        color = output.on and "on_surface" or "on_surface_variant",
        maxLines = 1,
      }),
      ui.label({
        text = output.on and (output.mode .. "  ·  " .. output.description)
          or (output.description ~= "" and output.description or "Off"),
        fontSize = 11,
        color = "on_surface_variant",
        maxLines = 1,
      }),
    }),
  }

  -- The only screen is of course the focused one.
  if output.focused and #outputs > 1 then
    table.insert(children, ui.glyph({ key = "focused", name = "check", size = 16, color = "primary" }))
  end

  -- The command refuses to blank the last lit screen either way; a switch that
  -- only ever errors is worse than one that says up front it will not move.
  local last = output.on and litCount() <= 1

  table.insert(children, ui.toggle({
    key = "power",
    checked = output.on,
    enabled = busy == "" and not last,
    onChange = function(checked)
      runAction("toggle:" .. output.name,
        TOGGLE_CMD .. " " .. shared.shellQuote(output.name) .. (checked and " on" or " off"),
        "Could not turn " .. output.name .. (checked and " on" or " off"))
    end,
  }))

  return ui.row({
    key = "card:" .. output.name,
    gap = 10,
    align = "center",
    radius = 10,
    padding = 10,
    border = "outline",
    borderWidth = 1,
  }, children)
end

function render()
  local body = {}

  for _, node in ipairs(brightnessSection()) do
    table.insert(body, node)
  end
  for _, node in ipairs(textSizeSection()) do
    table.insert(body, node)
  end
  for _, node in ipairs(scaleSection()) do
    table.insert(body, node)
  end

  table.insert(body, ui.separator({ key = "sep:displays" }))
  table.insert(body, sectionHeader("head:displays", #outputs == 1 and "DISPLAY" or "DISPLAYS", ""))

  if #outputs == 0 then
    table.insert(body, ui.label({
      text = loaded and "niri reports no displays" or "Reading the displays…",
      fontSize = 12,
      color = "on_surface_variant",
    }))
  end

  for _, output in ipairs(outputs) do
    table.insert(body, outputRow(output))
  end

  -- Placement needs a canvas this panel has no room for.
  if ARRANGE then
    table.insert(body, ui.row({ key = "row:arrange", gap = 8, align = "center" }, {
      ui.button({
        key = "arrange",
        text = "Arrange displays…",
        glyph = "layout-grid",
        variant = "outline",
        controlSize = "sm",
        onClick = "onArrangeClicked",
      }),
      ui.spacer({ flexGrow = 1 }),
    }))
  end

  if errorText ~= "" then
    table.insert(body, ui.label({ text = errorText, fontSize = 12, color = "error", maxWidth = 380 }))
  end

  local focused = focusedOutput()
  local subtitle = focused and (focused.mode ~= "" and (focused.name .. "  ·  " .. focused.mode) or focused.name)
    or "No display"

  panel.render(ui.column({ flexGrow = 1, gap = 12 }, {
    ui.row({ align = "center", gap = 10 }, {
      ui.glyph({ name = "device-desktop", size = 30, color = "primary" }),
      ui.column({ gap = 2, flexGrow = 1 }, {
        ui.label({ text = "Display", fontSize = 15, fontWeight = "bold", color = "on_surface" }),
        ui.label({ text = subtitle, fontSize = 11, color = "on_surface_variant", maxLines = 1 }),
      }),
      ui.button({ key = "close", glyph = "close", variant = "ghost", onClick = "onCloseClicked" }),
    }),

    ui.scroll({ flexGrow = 1, gap = 12 }, body),
  }))
end

-- Every open re-reads: a monitor plugged in meanwhile is what this is opened for.
function onOpen(_context)
  loaded = false
  busy = ""
  errorText = ""
  pendingPercent = nil
  liveBrightness = {}
  sending = {}
  queuedBrightness = {}
  brightTicks = 0
  panel.setWantsSecondTicks(true)
  render()
  refresh()
end

-- Commit a settled text size, and keep the brightness sliders honest against the
-- keys. Nothing else here moves on its own, so niri is not re-read on a tick.
function update()
  brightTicks += 1
  if brightTicks >= BRIGHT_POLL then
    brightTicks = 0
    readBrightness()
  end

  if pendingPercent == nil then
    return
  end

  settleTicks += 1
  if settleTicks < SETTLE then
    return
  end

  local percent = pendingPercent
  pendingPercent = nil
  settleTicks = 0

  if percent ~= textPercent then
    textPercent = percent
    runAction("text", TEXT_CMD .. " " .. percent, "Could not change the text size")
  end
end

function onClose()
  generation += 1
  panel.setWantsSecondTicks(false)
  pendingPercent = nil
  liveBrightness = {}
  queuedBrightness = {}
  busy = ""
end

function onCloseClicked()
  panel.close()
end

-- Focus rather than launch a second copy: two windows arguing about one file is
-- the problem this whole arrangement exists to avoid.
function onArrangeClicked()
  noctalia.runAsync(FOCUS_CMD .. " nwg-displays")
  panel.close()
end

function onKey(chord, pressed)
  if pressed and chord == "escape" then
    panel.close()
  end
end
