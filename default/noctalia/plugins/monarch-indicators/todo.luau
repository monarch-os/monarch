--!strict
-- Open-task indicator: the glyph alone, no count in the bar. Ports the v4
-- CustomButton that monarch-install-todo used to splice into settings.json with
-- jq — declaring it here instead means the install and remove commands no
-- longer have to edit the bar layout at all.
--
-- monarch-todo is install-on-demand, so the widget hides itself when the command
-- is missing rather than being added to and removed from the bar.
--
-- Polled, not streamed: `monarch-todo bar` is a one-shot command, matching the
-- v4 textIntervalMs = 10000. The count comes from that command, so no store
-- logic is duplicated here.

local indicator = require("./indicator.luau")

-- Package binary, so /usr/bin rather than the repo's bin/ (indicator.pkgBin).
local TODO_CMD = indicator.pkgBin("monarch-todo")
local POLL_MS = 10000

noctalia.setUpdateInterval(POLL_MS)
barWidget.setGlyph("checkbox")
barWidget.setVisible(false)

-- The pill shows the glyph alone. `monarch-todo bar` still reports the open
-- count in `text`, but it is only read as a presence signal — an empty object is
-- how the command says "no open tasks", which collapses the pill the way v4's
-- hideMode = "expandWithOutput" did. The count itself stays in the tooltip.
local function apply(payload)
  local text = if type(payload) == "table" then payload.text else nil

  if type(text) ~= "string" or text == "" then
    barWidget.clearTooltip()
    barWidget.setVisible(false)
    return
  end

  barWidget.setVisible(true)

  local tooltip = payload.tooltip
  if type(tooltip) == "string" and tooltip ~= "" then
    barWidget.setTooltip(tooltip)
  else
    barWidget.clearTooltip()
  end
end

function update()
  if not noctalia.fileExists(TODO_CMD) then
    barWidget.setVisible(false)
    return
  end

  noctalia.runAsync(TODO_CMD .. " bar", function(result)
    if result.exitCode ~= 0 then
      barWidget.setVisible(false)
      return
    end
    local payload = noctalia.json.decode(result.stdout)
    if payload then
      apply(payload)
    else
      barWidget.setVisible(false)
    end
  end)
end

function onClick()
  noctalia.runAsync(indicator.bin("monarch-launch-tui") .. " monarch-todo")
end
