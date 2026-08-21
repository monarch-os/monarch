--!nonstrict
-- The bar pill, in the place of the stock `brightness` widget: it replaces that
-- one rather than sitting beside it, so the lane keeps one screen glyph.

local shared = require("./shared.luau")

local LIST_CMD = shared.bin("monarch-display-list")

-- Content posted before the first tick is dropped, so this is set from update().
-- The hour is because nothing here moves on its own.
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

  -- The gesture is invisible otherwise.
  table.insert(lines, "Scroll to dim")
  return table.concat(lines, "\n")
end

function onClick()
  noctalia.togglePanel("monarch/display:panel")
end

-- What the stock brightness widget bound here, or the swap reads as broken.
-- steps is negative upwards.
function onScroll(_axis, steps, _startsGesture)
  noctalia.runAsync("noctalia msg brightness-" .. ((tonumber(steps) or 0) < 0 and "up" or "down"))
end

-- On hover and not polled: an idle bar has no business shelling out to niri.
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
