--!strict
-- The bar button, formerly BarWidget.qml: the mark of the agent in use,
-- clicking through to the panel. No percentage — the numbers live in the
-- tooltip and the panel.
--
-- Self-hiding: a machine that has never run a coding agent has no usage record,
-- so there is nothing to name and the button collapses out of the bar rather
-- than sitting there pointing at nothing.

local agents = require("./agents.luau")

local warningThreshold = tonumber(noctalia.getConfig("warning_threshold")) or 0.9
if warningThreshold <= 0 or warningThreshold > 1 then
  warningThreshold = 0.9
end

local function tooltipFor(records: { any }): string
  local lines: { string } = {}
  for _, record in ipairs(records) do
    local plan = tostring(record.tierLabel or "")
    local name = tostring(record.name or record.id or "")
    table.insert(lines, if plan ~= "" then name .. " · " .. plan else name)
    for _, limit in ipairs(record.limits or {}) do
      local percent = tonumber(limit.percent)
      if percent and percent >= 0 then
        local title = tostring(limit.title or limit.label or "")
        table.insert(lines, "  " .. title .. ": " .. tostring(math.floor(percent * 100 + 0.5)) .. "%")
      end
    end
  end
  return table.concat(lines, "\n")
end

local function apply()
  local records = noctalia.state.get(agents.KEY_RECORDS) or {}
  if #records == 0 then
    barWidget.clearTooltip()
    barWidget.setVisible(false)
    return
  end

  barWidget.setVisible(true)

  -- The mark of the first agent that reported. An agent whose mark this plugin
  -- does not ship still earns a button, falling back to the generic glyph.
  local agentId = tostring(records[1].id or "")
  local mark = agents.markPath(agentId)
  if mark then
    barWidget.setImage(mark)
  else
    barWidget.setGlyph("ai")
  end

  -- Past the threshold the mark is tinted with the error role. Below it the
  -- mark keeps its own brand colours — the bar carries no number, so this is
  -- the only at-a-glance warning that an allowance is nearly spent.
  local worst = tonumber(noctalia.state.get(agents.KEY_WORST)) or -1
  if worst >= warningThreshold then
    barWidget.setGlyphColor("error")
    barWidget.setColor("error")
  else
    barWidget.setGlyphColor("on_surface")
    barWidget.setColor("on_surface")
  end

  barWidget.setTooltip(tooltipFor(records))
end

barWidget.setVisible(false)
noctalia.state.watch(agents.KEY_RECORDS, apply)
noctalia.state.watch(agents.KEY_WORST, apply)
apply()

function onClick()
  noctalia.togglePanel("monarch/agents:details")
end

-- v4 refreshed on right-click. Only the service owns the collector, so ask it.
function onRightClick()
  noctalia.runAsync("noctalia msg plugin monarch/agents:collector all refresh")
end
