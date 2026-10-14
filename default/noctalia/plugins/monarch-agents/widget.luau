local data = require("./data.luau")

local function render()
  barWidget.render(ui.glyph({ name = "robot", size = 16, color = "on_surface" }))
  local tooltip = {}
  for _, provider in ipairs(noctalia.state.get("providers") or {}) do
    local lines = {}
    local issue = data.error(provider)
    if issue ~= "" then lines[#lines + 1] = issue end
    for _, window in ipairs(data.windows(provider)) do
      lines[#lines + 1] = window.title .. ": " .. noctalia.tr("ui.used", { percent = string.format("%.1f", window.used) })
    end
    local balance = data.balance(provider)
    if balance then lines[#lines + 1] = noctalia.tr("ui.balance", { amount = balance }) end
    local spend = data.spend(provider)
    if spend then
      lines[#lines + 1] = data.spendText(spend)
      if spend.period ~= "" then lines[#lines + 1] = spend.period end
    end
    tooltip[#tooltip + 1] = { key = data.name(provider), value = table.concat(lines, "\n") }
  end
  local issue = noctalia.state.get("error") or ""
  if issue ~= "" then tooltip[#tooltip + 1] = { key = noctalia.tr("ui.status"), value = noctalia.tr(issue) } end
  if #tooltip == 0 then tooltip[1] = { key = noctalia.tr("ui.title"), value = noctalia.tr("ui.waiting") } end
  barWidget.setTooltip(tooltip)
end

function onClick() noctalia.togglePanel("monarch/agents:details") end
function onRightClick() noctalia.state.set("command", { action = "refresh" }) end
noctalia.state.watch("providers", render)
noctalia.state.watch("error", render)
render()
