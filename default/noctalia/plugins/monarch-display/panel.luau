--!nonstrict
-- The display panel: what each screen is doing, and the things about it that
-- only the compositor can change.
--
-- Laid out after quattro's omarchy.monitor, which is the one to beat: a header
-- carrying the focused screen, then sections whose value sits on their own
-- header line, then the screens themselves. Scale acts on the focused output,
-- as it does there — one row of choices rather than a control buried in every
-- card.
--
-- Everything it knows comes from Monarch commands printing tab-separated
-- fields, so the logic that talks to niri stays in bash where it can be tested
-- without a compositor. This file is presentation and sequencing only.

local shared = require("./shared.luau")

local LIST_CMD = shared.bin("monarch-display-list")
local SCALE_CMD = shared.bin("monarch-display-scale")
local TOGGLE_CMD = shared.bin("monarch-display-toggle")
local TEXT_CMD = shared.bin("monarch-display-text-size")

-- The same set Mod+Ctrl+D cycles through, so the two ways in agree.
local SCALES = { "1", "1.25", "1.6", "2", "3", "4" }
local TEXT_STEP = 5
local TEXT_MIN = 75
local TEXT_MAX = 175

local outputs = {}
local textPercent = 100
local loaded = false
-- The action in flight ("" when idle). One at a time: these all reload niri's
-- config, and a second write landing mid-reload is not worth allowing for.
local busy = ""
local errorText = ""

-- The slider moves far faster than the command behind it can keep up with —
-- every step rewrites two files and pokes gsettings — so a drag parks its value
-- here and the tick below commits it once it settles. quattro debounces its own
-- brightness the same way, at 16ms.
local pendingPercent = nil
local settleTicks = 0
local SETTLE = 1

-- A read started before the last click must not land its stale answer on top
-- of the newer state.
local generation = 0

local render

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

local function focusedOutput()
  for _, output in ipairs(outputs) do
    if output.focused then
      return output
    end
  end
  -- Nothing focused is possible mid-transition; the first lit screen is a
  -- better guess than refusing to draw the scale row at all.
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

  noctalia.runAsync(TEXT_CMD .. " --current", function(result)
    if ticket ~= generation then return end
    if result and result.exitCode == 0 and pendingPercent == nil then
      textPercent = tonumber((result.stdout or ""):match("%d+")) or textPercent
    end
    render()
  end)
end

-- Every action ends the same way: clear the token, keep whatever the command
-- said on stderr, and re-read rather than guess at the new state. The refusal to
-- blank the last lit screen speaks through exactly this path.
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

-- ── Rendering ────────────────────────────────────────────────────────────────

-- Label left, value right, on one line: the shape quattro gives every section,
-- and the reason its panel reads as a panel rather than a form.
local function sectionHeader(text: string, value: string?): any
  return ui.row({ align = "center", gap = 8 }, {
    ui.label({ text = text, fontSize = 11, fontWeight = "medium", color = "on_surface_variant", flexGrow = 1 }),
    ui.label({ text = value or "", fontSize = 11, fontWeight = "medium", color = "on_surface" }),
  })
end

local function textSizeSection(): { any }
  return {
    sectionHeader("TEXT SIZE", (pendingPercent or textPercent) .. "%"),
    ui.slider({
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

-- Pills and not a dropdown, and on the focused screen rather than inside every
-- card: the choice is short, the values are worth reading at a glance, and it
-- is the shape quattro settled on.
local function scaleSection(): { any }
  local focused = focusedOutput()
  if not focused or not focused.on then
    return {}
  end

  local current = tonumber(focused.scale)
  local choices = table.clone(SCALES)

  -- niri prints 1.0 where the preset list says 1, so a scale is matched on its
  -- number and never on its text. One that is genuinely not a preset is added,
  -- or it could never be picked back from here.
  local known = false
  for _, value in ipairs(choices) do
    known = known or (current ~= nil and tonumber(value) == current)
  end
  if current and not known then
    table.insert(choices, focused.scale)
    table.sort(choices, function(a, b)
      return (tonumber(a) or 0) < (tonumber(b) or 0)
    end)
  end

  local pills = {}
  for _, value in ipairs(choices) do
    local active = current ~= nil and tonumber(value) == current
    table.insert(pills, ui.button({
      text = value .. "x",
      variant = active and "primary" or "outline",
      controlSize = "sm",
      enabled = busy == "" and not active,
      onClick = function()
        runAction("scale", SCALE_CMD .. " " .. shared.shellQuote(focused.name) .. " " .. shared.shellQuote(value),
          "Could not scale " .. focused.name)
      end,
    }))
  end

  return {
    ui.separator({}),
    sectionHeader("SCALE", focused.name),
    ui.row({ gap = 6, align = "center" }, pills),
  }
end

local function outputRow(output): any
  local label = output.name
  if output.focused then
    label ..= "  ·  focused"
  end

  -- A plain row and not ui.box: its `fill` takes a literal colour, not a role
  -- name, and a box given one simply does not draw. Focus is said in the label
  -- instead, which is what it is for.
  return ui.row({ gap = 10, align = "center" }, {
      ui.glyph({
        name = output.on and "device-desktop" or "device-desktop-off",
        size = 18,
        color = output.on and "on_surface" or "on_surface_variant",
      }),
      ui.column({ gap = 2, flexGrow = 1 }, {
        ui.label({
          text = label,
          fontSize = 13,
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
      ui.toggle({
        checked = output.on,
        onChange = function(checked)
          runAction("toggle:" .. output.name,
            TOGGLE_CMD .. " " .. shared.shellQuote(output.name) .. (checked and " on" or " off"),
            "Could not turn " .. output.name .. (checked and " on" or " off"))
        end,
      }),
  })
end

function render()
  local body = {}

  for _, node in ipairs(textSizeSection()) do
    table.insert(body, node)
  end
  for _, node in ipairs(scaleSection()) do
    table.insert(body, node)
  end

  table.insert(body, ui.separator({}))
  table.insert(body, sectionHeader(#outputs == 1 and "DISPLAY" or "DISPLAYS", ""))

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

  -- Where the refusal to blank the last lit screen surfaces, among the rest.
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
      -- The brightness this panel deliberately does not carry, one click away
      -- in the control center tab that owns the per-display sliders. The pill's
      -- click used to land there directly.
      ui.button({
        glyph = "sun",
        variant = "ghost",
        controlSize = "sm",
        tooltip = "Brightness",
        onClick = "onBrightnessClicked",
      }),
      ui.button({ glyph = "close", variant = "ghost", onClick = "onCloseClicked" }),
    }),

    ui.scroll({ flexGrow = 1, gap = 12 }, body),
  }))
end

-- Every open re-reads: a monitor plugged in while this was closed is exactly
-- what the panel gets opened to deal with.
function onOpen(_context)
  loaded = false
  busy = ""
  errorText = ""
  pendingPercent = nil
  panel.setWantsSecondTicks(true)
  render()
  refresh()
end

-- Only here to commit a settled slider; nothing else on this panel moves on its
-- own, and re-reading niri every second to be told the same thing would be rude.
function update()
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
  busy = ""
end

function onCloseClicked()
  panel.close()
end

-- The control center is not a plugin panel, so togglePanel cannot name it and
-- the tab has to be an argument; this is the same verb the stock brightness
-- widget's own left click sends.
function onBrightnessClicked()
  noctalia.runAsync("noctalia msg panel-toggle control-center monitor")
  panel.close()
end

function onKey(chord, pressed)
  if pressed and chord == "escape" then
    panel.close()
  end
end
