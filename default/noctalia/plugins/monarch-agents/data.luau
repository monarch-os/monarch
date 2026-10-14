local M = {}

function M.name(provider)
  local id = tostring(provider.provider or provider.id or "unknown")
  local names = { codex = "Codex", claude = "Claude", synthetic = "Synthetic", openrouter = "OpenRouter" }
  return names[id] or (string.upper(string.sub(id, 1, 1)) .. string.sub(id, 2))
end

function M.error(provider)
  local issue = provider.error
  if type(issue) == "table" then
    return tostring(issue.message or issue.description or issue.kind or "Provider unavailable")
  end
  return issue and tostring(issue) or ""
end

function M.windows(provider)
  local usage = provider.usage or {}
  local labels = provider.rateWindowLabels or {}
  local rows = {}
  local seen = {}
  local function add(key, window, label)
    if type(window) ~= "table" or window.usageKnown == false or seen[window] or tonumber(window.usedPercent) == nil then return end
    seen[window] = true
    rows[#rows + 1] = {
      title = label or labels[key] or window.title or window.label or key,
      used = math.max(0, math.min(100, tonumber(window.usedPercent))),
      reset = window.resetsAt,
    }
  end
  for _, key in ipairs({ "primary", "secondary", "tertiary" }) do
    add(key, usage[key])
  end
  for _, extra in ipairs(usage.extraRateWindows or {}) do
    if extra.usageKnown ~= false then
      add("Additional quota", extra.window or extra, extra.title or extra.name)
    end
  end
  for _, extra in ipairs(usage.windows or {}) do
    add("Quota", extra.window or extra, extra.title or extra.name)
  end
  return rows
end

function M.balance(provider)
  local cost = (provider.usage or {}).providerCost
  if type(cost) ~= "table" or cost.balance == nil then return nil end
  return tostring(cost.balance) .. (cost.currencyCode and (" " .. tostring(cost.currencyCode)) or "")
end

function M.color(used)
  if used >= 90 then return "error" end
  if used >= 70 then return "tertiary" end
  return "primary"
end

return M
