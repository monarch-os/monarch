--!strict
-- Shared driver for Monarch's three bar indicators.
--
-- Each indicator is a bash script under default/noctalia/indicators/ that emits
-- one JSON object per line: {} to hide, or {text, tooltip?, textColor?} to
-- show. That is exactly what the v4 CustomButton consumed in textStream +
-- parseJson mode, so the scripts carry over untouched and this module only
-- translates their output onto the v5 barWidget setters.
--
-- v4's hideMode = "expandWithOutput" collapsed the widget when the text was
-- empty; setVisible(false) is the v5 equivalent.

local M = {}

-- Mirrors the MONARCH_ROOT fallback used across bin/: honour MONARCH_PATH when
-- the session exports it, else assume the stock install location.
local function monarchRoot(): string
  local fromEnv = noctalia.getenv("MONARCH_PATH")
  if fromEnv and fromEnv ~= "" then
    return fromEnv
  end
  return noctalia.expandPath("~/.local/share/monarch")
end

function M.indicatorPath(name: string): string
  return monarchRoot() .. "/default/noctalia/indicators/" .. name
end

-- Absolute path to a Monarch command. Noctalia is started by the compositor,
-- not a login shell, so its PATH is only /usr/local/sbin:/usr/local/bin:/usr/bin
-- — Monarch's bin/ is absent and a bare command name silently fails to launch.
-- Every command a plugin runs must go through here.
function M.bin(name: string): string
  return monarchRoot() .. "/bin/" .. name
end

-- Apply one decoded payload. An empty object (or one with no text) hides the
-- widget, which is how the scripts signal "nothing to report".
local function apply(payload)
  local text = if type(payload) == "table" then payload.text else nil

  if type(text) ~= "string" or text == "" then
    barWidget.clearTooltip()
    barWidget.setVisible(false)
    return
  end

  barWidget.setText(text)
  barWidget.setVisible(true)

  local tooltip = payload.tooltip
  if type(tooltip) == "string" and tooltip ~= "" then
    barWidget.setTooltip(tooltip)
  else
    barWidget.clearTooltip()
  end

  -- textColor carries a palette role name ("error"), not a hex value; the
  -- scripts only ever set it to flag an active state.
  local color = payload.textColor
  if type(color) == "string" and color ~= "" then
    barWidget.setColor(color)
  end
end

-- Start streaming `script`. Lines that are not valid JSON are logged and
-- skipped rather than left to blank the widget, so a transient failure in a
-- script does not silently make the indicator disappear.
function M.stream(script: string)
  barWidget.setVisible(false)

  local path = M.indicatorPath(script)
  local ok = noctalia.runStream(path, function(line: string)
    if line == "" then
      return
    end
    local payload, err = noctalia.json.decode(line)
    if not payload then
      noctalia.log("indicator " .. script .. ": bad JSON line: " .. tostring(err))
      return
    end
    apply(payload)
  end)

  if not ok then
    noctalia.log("indicator " .. script .. ": failed to start " .. path)
  end
end

return M
