--!strict
-- The display side, formerly Panel.qml: for each agent record, its plan, the
-- percentage of each allowance already spent with the window's reset time, the
-- last week of token totals, and the all-time per-model breakdown.
--
-- Strictly a display. Everything here comes off the records the service
-- publishes, so an agent gains a panel section by gaining a collector.

local agents = require("./agents.luau")

-- Every bar in a chart is scaled to that chart's own busiest row, so a quiet
-- week still reads as a shape rather than seven flat lines.
local function ratio(value: number, peak: number): number
  if peak <= 0 then
    return 0
  end
  local r = value / peak
  return if r > 1 then 1 else r
end

local function limitRows(record: any): { any }
  local rows = {}
  for index, limit in ipairs(record.limits or {}) do
    local percent = tonumber(limit.percent) or 0
    if percent < 0 then
      percent = 0
    end
    local title = tostring(limit.title or limit.label or "")
    local reset = agents.formatReset(limit.resetsAt)

    table.insert(rows, ui.column({ key = "limit-" .. index, gap = 4 }, {
      ui.row({ gap = 8, align = "center" }, {
        ui.label({ text = title, flexGrow = 1 }),
        ui.label({
          text = tostring(math.floor(percent * 100 + 0.5)) .. "%",
          color = agents.severityRole(percent),
          fontWeight = "bold",
        }),
      }),
      ui.progress({ progress = percent, height = 6, color = agents.severityRole(percent) }),
      -- An absent or unparseable reset time yields "", and the row is omitted
      -- rather than printed empty.
      if reset ~= "" then ui.label({ text = "resets " .. reset, fontSize = 11, color = "on_surface/0.6" }) else ui.spacer({ height = 0 }),
    }))
  end
  return rows
end

local function dayRows(record: any): { any }
  local days = record.recentDays or {}
  local peak = 0
  for _, day in ipairs(days) do
    local n = tonumber(day.messageCount) or 0
    if n > peak then
      peak = n
    end
  end

  local rows = {}
  for index, day in ipairs(days) do
    local tokens = tonumber(day.messageCount) or 0
    local isToday = index == #days
    table.insert(rows, ui.row({ key = "day-" .. index, gap = 8, align = "center" }, {
      ui.label({
        text = agents.dayLabel(day.date),
        width = 40,
        fontSize = 11,
        color = if isToday then "primary" else "on_surface/0.7",
      }),
      ui.progress({ progress = ratio(tokens, peak), flexGrow = 1, height = 6 }),
      ui.label({ text = agents.formatTokens(tokens), width = 56, fontSize = 11 }),
    }))
  end
  return rows
end

local function modelRows(record: any): { any }
  -- modelUsage is a map; flatten and sort heaviest first so the chart has a
  -- stable order and a meaningful peak.
  local entries = {}
  for name, value in pairs(record.modelUsage or {}) do
    local total = if type(value) == "table" then tonumber(value.total) else tonumber(value)
    table.insert(entries, { name = tostring(name), total = total or 0 })
  end
  table.sort(entries, function(a, b)
    return a.total > b.total
  end)

  local peak = if #entries > 0 then entries[1].total else 0
  local rows = {}
  for index, entry in ipairs(entries) do
    table.insert(rows, ui.row({ key = "model-" .. index, gap = 8, align = "center" }, {
      ui.label({ text = entry.name, width = 120, fontSize = 11, color = "on_surface/0.7" }),
      ui.progress({ progress = ratio(entry.total, peak), flexGrow = 1, height = 6 }),
      ui.label({ text = agents.formatTokens(entry.total), width = 56, fontSize = 11 }),
    }))
  end
  return rows
end

local function section(title: string, rows: { any }): any
  if #rows == 0 then
    return ui.spacer({ height = 0 })
  end
  return ui.column({ gap = 6 }, {
    ui.label({ text = title, fontSize = 11, fontWeight = "bold", color = "on_surface/0.6" }),
    ui.column({ gap = 6 }, rows),
  })
end

local function agentSection(record: any, index: number): any
  local name = tostring(record.name or record.id or "")
  local plan = tostring(record.tierLabel or "")
  local mark = agents.markPath(tostring(record.id or ""))

  local hero = {}
  if mark then
    table.insert(hero, ui.image({ path = mark, width = 24, height = 24 }))
  else
    table.insert(hero, ui.glyph({ name = "ai", size = 24 }))
  end
  table.insert(hero, ui.column({ gap = 0, flexGrow = 1 }, {
    ui.label({ text = name, fontWeight = "bold" }),
    if plan ~= "" then ui.label({ text = plan, fontSize = 11, color = "on_surface/0.6" }) else ui.spacer({ height = 0 }),
  }))

  return ui.column({ key = "agent-" .. index, gap = 12 }, {
    ui.row({ gap = 10, align = "center" }, hero),
    section("Limits", limitRows(record)),
    section("Last 7 days", dayRows(record)),
    section("By model", modelRows(record)),
    ui.separator({}),
  })
end

local function render()
  local records = noctalia.state.get(agents.KEY_RECORDS) or {}

  if #records == 0 then
    panel.render(ui.column({ gap = 12, padding = 16 }, {
      ui.label({ text = "Agents", fontSize = 18, fontWeight = "bold" }),
      ui.label({
        text = "No coding agent has reported usage yet.",
        color = "on_surface/0.6",
      }),
    }))
    return
  end

  local sections = {}
  for index, record in ipairs(records) do
    table.insert(sections, agentSection(record, index))
  end

  panel.render(ui.column({ gap = 12, padding = 16 }, {
    ui.label({ text = "Agents", fontSize = 18, fontWeight = "bold" }),
    ui.scroll({ flexGrow = 1 }, sections),
  }))
end

function onOpen()
  render()
  -- Records keep arriving while the panel is open; redraw rather than freeze
  -- on whatever was current at open time.
  noctalia.state.watch(agents.KEY_RECORDS, render)
end
