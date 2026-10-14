local data = require("./data.luau")
local selectedId = nil
local opened = false
local render

local function providerId(provider)
  return tostring(provider.provider or provider.id or "unknown") .. ":" .. tostring(provider.account or "")
end

local function providerSection(provider)
  local usage = provider.usage or {}
  local identity = usage.identity or {}
  local children = {
    ui.row({ gap = 10, align = "center" }, {
      ui.glyph({ name = "robot", size = 24, color = "primary" }),
      ui.column({ gap = 2, flexGrow = 1 }, {
        ui.label({ text = data.name(provider), fontWeight = "bold", fontSize = 16 }),
        ui.label({ text = tostring(identity.plan or identity.accountEmail or provider.source or ""), fontSize = 11, color = "on_surface/0.6" }),
      }),
    }),
  }
  local issue = data.error(provider)
  if issue ~= "" then
    children[#children + 1] = ui.label({ text = issue, color = "error", maxLines = 4 })
  end
  for _, window in ipairs(data.windows(provider)) do
    local rows = {
      ui.row({ gap = 8, align = "center" }, {
        ui.label({ text = window.title, flexGrow = 1 }),
        ui.label({ text = string.format("%.1f%%", window.used), fontWeight = "bold", color = data.color(window.used) }),
      }),
      ui.progress({ progress = window.used / 100, height = 6, color = data.color(window.used) }),
    }
    if window.reset then
      local reset = tostring(window.reset)
      reset = string.gsub(reset, "^(%d%d%d%d%-%d%d%-%d%d)T(%d%d:%d%d):%d%dZ$", "%1 %2 UTC")
      rows[#rows + 1] = ui.label({ text = "Resets " .. reset, fontSize = 11, color = "on_surface/0.6" })
    end
    children[#children + 1] = ui.column({ gap = 4 }, rows)
  end
  local credits = provider.credits or usage.credits
  if type(credits) == "table" and credits.remaining ~= nil then
    children[#children + 1] = ui.label({ text = "Credits remaining: " .. tostring(credits.remaining) })
  end
  if #data.windows(provider) == 0 and issue == "" and not credits then
    children[#children + 1] = ui.label({ text = "No quota reported", color = "on_surface/0.6" })
  end
  if provider.stale then
    children[#children + 1] = ui.label({ text = "Last known data", fontSize = 11, color = "tertiary" })
  end
  return ui.column({ gap = 16 }, children)
end

render = function()
  if not opened then return end
  local providers = noctalia.state.get("providers") or {}
  local children = {
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = "Agents", fontSize = 18, fontWeight = "bold", flexGrow = 1 }),
      ui.button({ glyph = "refresh", variant = "ghost", onClick = "onRefresh", tooltip = "Refresh quotas" }),
    }),
  }
  local selected = providers[1]
  local buttons = {}
  for _, provider in ipairs(providers) do
    if providerId(provider) == selectedId then selected = provider end
  end
  if selected then selectedId = providerId(selected) end
  for _, provider in ipairs(providers) do
    local id = providerId(provider)
    buttons[#buttons + 1] = ui.button({
      text = data.name(provider), controlSize = "sm",
      flexGrow = 1,
      variant = id == selectedId and "primary" or "outline",
      onClick = function() selectedId = id; render() end,
    })
  end
  if #buttons > 1 then
    local rows = {}
    for index = 1, #buttons, 3 do
      local cells = {}
      for offset = 0, 2 do
        if buttons[index + offset] then cells[#cells + 1] = buttons[index + offset] end
      end
      rows[#rows + 1] = ui.row({ gap = 6 }, cells)
    end
    children[#children + 1] = ui.scroll({ height = math.min(96, #rows * 38) }, { ui.column({ gap = 6 }, rows) })
  end
  children[#children + 1] = ui.scroll({ flexGrow = 1 }, {
    selected and providerSection(selected) or ui.label({ text = "No provider enabled. Configure one below.", color = "on_surface/0.6" }),
  })
  local issue = noctalia.state.get("error") or ""
  if issue ~= "" then
    children[#children + 1] = ui.label({ text = issue, fontSize = 11, color = "error", maxLines = 2 })
  end
  children[#children + 1] = ui.button({ text = "Manage providers", glyph = "settings", onClick = "onManageProviders" })
  panel.render(ui.column({ flexGrow = 1, gap = 12, padding = 16 }, children))
end

function onOpen() opened = true; render() end
function onClose() opened = false end
function onRefresh() noctalia.state.set("command", { action = "refresh" }) end
function onManageProviders()
  panel.close()
  noctalia.runAsync("/usr/bin/monarch-launch-tui --app-id=org.monarch.agent-usage /usr/bin/monarch-agent-usage manage")
end
noctalia.state.watch("providers", render)
noctalia.state.watch("error", render)
