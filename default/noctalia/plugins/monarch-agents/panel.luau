--!strict
-- The display side, formerly Panel.qml: for each agent record, its plan, the
-- percentage of each allowance already spent with the window's reset time, the
-- last week of token totals, and the all-time per-model breakdown.
--
-- Strictly a display. Everything here comes off the records the service
-- publishes, so an agent gains a panel section by gaining a collector.

local agents = require("./agents.luau")

local render

-- Which agent the panel is showing, held by id rather than by index: records
-- appear and vanish as collectors report, and an index would quietly start
-- pointing at a different agent the moment the list shifts.
local selectedId: string? = nil

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

  if peak <= 0 then
    return {}
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

-- A bucket carries the four raw counters and no total; summing them is the
-- caller's job. Reading a `total` field failed silently — nil, then 0, and
-- every bar in the chart rendered empty.
local function bucketTotal(value: any): number
  if type(value) == "number" then
    return value
  end
  if type(value) ~= "table" then
    return 0
  end
  return (tonumber(value.inputTokens) or 0)
    + (tonumber(value.outputTokens) or 0)
    + (tonumber(value.cacheReadInputTokens) or 0)
    + (tonumber(value.cacheCreationInputTokens) or 0)
end

local function modelRows(record: any): { any }
  -- modelUsage is a map; flatten and sort heaviest first so the chart has a
  -- stable order and a meaningful peak.
  local entries = {}
  for name, value in pairs(record.modelUsage or {}) do
    local total = bucketTotal(value)
    if total > 0 then
      table.insert(entries, { name = tostring(name), total = total })
    end
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

-- What the all-time numbers amount to, and — while the status says they are
-- not authoritative — how to make them so again.
local function footer(record: any): any
  local prompts = math.floor(tonumber(record.totalPrompts) or 0)
  local days = math.floor(tonumber(record.activeDays) or 0)
  local status = tostring(record.usageStatusText or "")
  local help = tostring(record.authHelpText or "")

  local cells = {
    ui.label({
      text = prompts .. " prompts over " .. days .. " days",
      fontSize = 11,
      color = "on_surface/0.6",
      flexGrow = 1,
    }),
  }
  if status ~= "" and help ~= "" then
    table.insert(cells, ui.label({ text = help, fontSize = 11, color = "error", maxLines = 2 }))
  end
  return ui.row({ gap = 8, align = "center" }, cells)
end

local function agentSection(record: any, index: number): any
  local name = tostring(record.name or record.id or "")
  -- The status wins the subtitle when there is one: "Waiting for auth" is
  -- worth more than the plan it would otherwise be sitting next to.
  local status = tostring(record.usageStatusText or "")
  local subtitle = if status ~= "" then status else tostring(record.tierLabel or "")
  local mark = agents.markPath(tostring(record.id or ""))

  local hero = {}
  if mark then
    table.insert(hero, ui.image({ path = mark, width = 24, height = 24 }))
  else
    table.insert(hero, ui.glyph({ name = "ai", size = 24 }))
  end
  table.insert(hero, ui.column({ gap = 0, flexGrow = 1 }, {
    ui.label({ text = name, fontWeight = "bold" }),
    if subtitle ~= "" then ui.label({ text = subtitle, fontSize = 11, color = "on_surface/0.6" }) else ui.spacer({ height = 0 }),
  }))
  table.insert(hero, ui.label({
    text = math.floor(tonumber(record.todayPrompts) or 0)
      .. " today · "
      .. agents.formatTokens(tonumber(record.todayTotalTokens) or 0),
    fontSize = 11,
    color = "on_surface/0.6",
  }))

  return ui.column({ key = "agent-" .. index, gap = 12 }, {
    ui.row({ gap = 10, align = "center" }, hero),
    section("Limits", limitRows(record)),
    section("Last 7 days", dayRows(record)),
    section("By model", modelRows(record)),
    footer(record),
  })
end

-- One button per reporting agent. Only drawn from the second agent onwards: a
-- lone button offers no choice, and every machine with one collector would
-- carry it for nothing.
local function selector(records: { any }): any
  local buttons = {}
  for index, record in ipairs(records) do
    local id = tostring(record.id or index)
    -- Outlined rather than ghosted, sharing the row evenly: the same pill shape
    -- the network panel uses for its DNS providers.
    table.insert(buttons, ui.button({
      key = "pick-" .. id,
      text = tostring(record.name or id),
      variant = if id == selectedId then "primary" else "outline",
      controlSize = "sm",
      flexGrow = 1,
      onClick = function()
        selectedId = id
        render()
      end,
    }))
  end
  return ui.row({ gap = 6, align = "center" }, buttons)
end

-- The selected record, or the first one when the selection names an agent that
-- has since stopped reporting.
local function selected(records: { any }): any
  for _, record in ipairs(records) do
    if tostring(record.id or "") == selectedId then
      return record
    end
  end
  local first = records[1]
  selectedId = tostring(first.id or "")
  return first
end

function render()
  local records = noctalia.state.get(agents.KEY_RECORDS) or {}

  if #records == 0 then
    panel.render(ui.column({ flexGrow = 1, gap = 12, padding = 16 }, {
      ui.label({ text = "Agents", fontSize = 18, fontWeight = "bold" }),
      ui.label({
        text = "No coding agent has reported usage yet.",
        color = "on_surface/0.6",
      }),
    }))
    return
  end

  local record = selected(records)

  local children = { ui.label({ text = "Agents", fontSize = 18, fontWeight = "bold" }) }
  if #records > 1 then
    table.insert(children, selector(records))
  end
  table.insert(children, ui.scroll({ flexGrow = 1, gap = 12 }, { agentSection(record, 1) }))

  -- flexGrow on the root as well as the scroll: the viewport grows into the
  -- panel's declared height, and without it collapses to a couple of rows.
  panel.render(ui.column({ flexGrow = 1, gap = 12, padding = 16 }, children))
end

function onOpen()
  render()
  -- Records keep arriving while the panel is open; redraw rather than freeze
  -- on whatever was current at open time.
  noctalia.state.watch(agents.KEY_RECORDS, render)
end
