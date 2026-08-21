--!strict
-- Where Monarch's commands live, and how to read what they print.
--
-- A copy of monarch-network's, because `require` is plugin-relative: there is
-- no way for one plugin to reach another's module.

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

-- Noctalia is started by the compositor, not a login shell, so its PATH is only
-- /usr/local/sbin:/usr/local/bin:/usr/bin — Monarch's bin/ is absent and a bare
-- command name silently fails to launch.
function M.bin(name: string): string
  return monarchRoot() .. "/bin/" .. name
end

-- runAsync's argv-table form needs plugin_api >= 24 and this plugin targets 22,
-- so arguments are quoted by hand.
function M.shellQuote(text: string): string
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

function M.trim(text: string): string
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- stderr if the command left any, the fallback otherwise.
function M.errorFrom(result, fallback: string): string
  local message = M.trim(result and result.stderr or "")
  return message ~= "" and message or fallback
end

return M
