--!nonstrict
-- The bar pill, in the place quattro gives omarchy.monitor and Monarch gave the
-- stock `brightness` widget.
--
-- It replaces that widget rather than sitting beside it, so the right lane keeps
-- one screen glyph instead of two. Nothing is lost by the swap: the scroll
-- gesture is re-bound to the same two IPC verbs below, and the tab its click
-- used to open — the control center's Monitor, which owns the brightness
-- sliders — is a button inside the panel this opens.

local shared = require("./shared.luau")

local LIST_CMD = shared.bin("monarch-display-list")

-- Set from update() and not at module load: the host draws a plugin widget from
-- what its tick produced, and content posted before the first tick is dropped.
-- The interval is long because nothing here changes on its own — the tooltip is
-- read on hover and the glyph never moves.
noctalia.setUpdateInterval(3600000)

function update()
  barWidget.setGlyph("device-desktop")
  barWidget.setVisible(true)
end

local function tooltipFrom(text: string): string
  local lines = {}

  for line in text:gmatch("[^\n]+") do
    local name, state, scale, mode = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)")
    if name and name ~= "" then
      if state == "on" then
        table.insert(lines, name .. " — " .. mode .. ", scale " .. scale)
      else
        table.insert(lines, name .. " — off")
      end
    end
  end

  -- The gesture is invisible otherwise, and it is the one thing this pill does
  -- that the panel cannot.
  table.insert(lines, "Scroll to dim")
  return table.concat(lines, "\n")
end

function onClick()
  noctalia.togglePanel("monarch/display:panel")
end

-- The stock brightness widget bound these to ScrollUp and ScrollDown, and a pill
-- standing in its place that did not would simply read as broken. steps is
-- negative upwards.
function onScroll(_axis, steps, _startsGesture)
  noctalia.runAsync("noctalia msg brightness-" .. ((tonumber(steps) or 0) < 0 and "up" or "down"))
end

-- Read on hover rather than polled: outputs change when a cable moves, which is
-- exactly when someone reaches for this, and an idle bar has no business
-- shelling out to niri every few seconds to be told the same thing.
function onHover(entered)
  if tostring(entered) ~= "true" then
    return
  end

  noctalia.runAsync(LIST_CMD, function(result)
    if result and result.exitCode == 0 and (result.stdout or "") ~= "" then
      barWidget.setTooltip(tooltipFrom(result.stdout))
    end
  end)
end
