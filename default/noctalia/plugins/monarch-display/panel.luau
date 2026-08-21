--!nonstrict
-- The display panel: what each output is doing, and the two things about it
-- that only the compositor can change.
--
-- No brightness slider. The control center's Monitor tab already draws one per
-- display over a service that speaks backlight and DDC both, and a second copy
-- here would be a worse one. Scale and on-off have no equivalent anywhere in
-- v5, which is the whole reason this exists.
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
-- config, and a second write landing mid-reload is not worth the complexity of
-- allowing it.
local busy = ""
local errorText = ""

-- A read started before the last click must not land its stale answer on top
-- of the newer state.
local generation = 0

local render

local function parseOutputs(text: string)
  local rows = {}

  for line in text:gmatch("[^\n]+") do
    -- Description last, being the only field that may contain a tab.
    local name, state, scale, mode, description =
      line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
    if name and name ~= "" then
      table.insert(rows, {
        name = name,
        on = state == "on",
        scale = scale,
        mode = mode,
        description = description,
      })
    end
  end

  return rows
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
    if result and result.exitCode == 0 then
      textPercent = tonumber((result.stdout or ""):match("%d+")) or textPercent
    end
    render()
  end)
end

-- Every action ends the same way: clear the token, keep whatever the command
-- said on stderr, and re-read rather than guess at the new state. The guard
-- that refuses the last lit screen speaks through exactly this path.
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

local function setTextPercent(percent: number)
  percent = math.max(TEXT_MIN, math.min(TEXT_MAX, percent))
  if percent == textPercent then
    return
  end
  runAction("text", TEXT_CMD .. " " .. percent, "Could not change the text size")
end

-- ── Rendering ────────────────────────────────────────────────────────────────

local function sectionHeader(text: string): any
  return ui.label({ text = text, fontSize = 11, fontWeight = "medium", color = "on_surface_variant" })
end

local function textSizeSection(): { any }
  return {
    sectionHeader("TEXT SIZE"),
    ui.row({ gap = 8, align = "center" }, {
      ui.button({
        text = "−",
        variant = "outline",
        controlSize = "sm",
        enabled = busy == "" and textPercent > TEXT_MIN,
        onClick = function()
          setTextPercent(textPercent - TEXT_STEP)
        end,
      }),
      ui.label({
        text = busy == "text" and "…" or (textPercent .. "%"),
        fontSize = 13,
        color = "on_surface",
      }),
      ui.button({
        text = "+",
        variant = "outline",
        controlSize = "sm",
        enabled = busy == "" and textPercent < TEXT_MAX,
        onClick = function()
          setTextPercent(textPercent + TEXT_STEP)
        end,
      }),
      ui.spacer({ flexGrow = 1 }),
      ui.button({
        text = "Reset",
        variant = "ghost",
        controlSize = "sm",
        enabled = busy == "" and textPercent ~= 100,
        onClick = function()
          setTextPercent(100)
        end,
      }),
    }),
    ui.label({
      text = "The bar, the panels, GTK apps and the terminal, together.",
      fontSize = 11,
      color = "on_surface_variant",
    }),
  }
end

-- niri prints 1.0 where the preset list says 1, so a scale is matched on its
-- number and never on its text — comparing the strings put both in the list.
-- A scale that is genuinely not a preset is still added, or picking it back
-- after a stray change would be impossible from here.
local function scaleChoices(current: string): ({ string }, number)
  local choices = table.clone(SCALES)
  local wanted = tonumber(current)
  local found = nil

  for index, value in ipairs(choices) do
    if wanted and tonumber(value) == wanted then
      found = index
      break
    end
  end

  if wanted and not found then
    table.insert(choices, current)
    table.sort(choices, function(a, b)
      return (tonumber(a) or 0) < (tonumber(b) or 0)
    end)
    found = table.find(choices, current)
  end

  return choices, (found or 1) - 1
end

local function outputCard(output): any
  local rows = {
    ui.row({ gap = 8, align = "center" }, {
      ui.column({ gap = 2, flexGrow = 1 }, {
        ui.label({ text = output.name, fontSize = 13, fontWeight = "medium", color = "on_surface" }),
        ui.label({
          text = output.description ~= "" and output.description or "Unknown display",
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
    }),
  }

  -- A dark output reports neither a mode nor a scale, and has nothing to scale.
  if output.on then
    local choices, selected = scaleChoices(output.scale)

    table.insert(rows, ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = output.mode, fontSize = 11, color = "on_surface_variant", flexGrow = 1 }),
      ui.label({ text = "Scale", fontSize = 12, color = "on_surface_variant" }),
      ui.select({
        options = choices,
        selectedIndex = selected,
        enabled = busy == "",
        onChange = function(_index, text)
          -- Same reason as above: 1 and 1.0 are the same scale.
          if tonumber(text) == tonumber(output.scale) then
            return
          end
          runAction("scale:" .. output.name,
            SCALE_CMD .. " " .. shared.shellQuote(output.name) .. " " .. shared.shellQuote(text),
            "Could not scale " .. output.name)
        end,
      }),
    }))
  end

  return ui.column({ gap = 6 }, rows)
end

function render()
  local body = {}

  for _, node in ipairs(textSizeSection()) do
    table.insert(body, node)
  end

  table.insert(body, ui.separator({}))
  table.insert(body, sectionHeader(#outputs == 1 and "DISPLAY" or "DISPLAYS"))

  if #outputs == 0 then
    table.insert(body, ui.label({
      text = loaded and "niri reports no displays" or "Reading the displays…",
      fontSize = 12,
      color = "on_surface_variant",
    }))
  end

  for _, output in ipairs(outputs) do
    table.insert(body, outputCard(output))
  end

  -- Where the refusal to blank the last lit screen surfaces, among the rest.
  if errorText ~= "" then
    table.insert(body, ui.label({ text = errorText, fontSize = 12, color = "error", maxWidth = 380 }))
  end

  panel.render(ui.column({ flexGrow = 1, gap = 12 }, {
    ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = "Displays", fontSize = 15, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
      ui.button({ glyph = "close", onClick = "onCloseClicked" }),
    }),

    ui.scroll({ flexGrow = 1, gap = 10 }, body),
  }))
end

-- Every open re-reads: a monitor plugged in while this was closed is exactly
-- what the panel is opened to deal with.
function onOpen(_context)
  loaded = false
  busy = ""
  errorText = ""
  render()
  refresh()
end

function onClose()
  generation += 1
  busy = ""
end

function onCloseClicked()
  panel.close()
end

function onKey(chord, pressed)
  if pressed and chord == "escape" then
    panel.close()
  end
end
