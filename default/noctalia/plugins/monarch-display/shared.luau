--!strict
-- A copy of monarch-network's: `require` is plugin-relative, so one plugin
-- cannot reach another's module.

local M = {}

local function monarchRoot(): string
  local fromEnv = noctalia.getenv("MONARCH_PATH")
  if fromEnv and fromEnv ~= "" then
    return fromEnv
  end
  return noctalia.expandPath("~/.local/share/monarch")
end

-- Noctalia is started by the compositor, so its PATH has no Monarch bin/ and a
-- bare command name silently fails to launch.
function M.bin(name: string): string
  return monarchRoot() .. "/bin/" .. name
end

-- runAsync's argv-table form needs plugin_api >= 24; this plugin targets 22.
function M.shellQuote(text: string): string
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

function M.trim(text: string): string
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.errorFrom(result, fallback: string): string
  local message = M.trim(result and result.stderr or "")
  return message ~= "" and message or fallback
end

return M
