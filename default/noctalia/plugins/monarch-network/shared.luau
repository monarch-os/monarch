--!strict
-- What the network widget and its two panels all need: where Monarch's commands
-- live, and how to read the `key<TAB>value` status they print.

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

-- key<TAB>value a line. The value takes the rest of the line, so an SSID
-- carrying a tab of its own survives the split.
function M.parseKeyValue(text: string): { [string]: string }
  local fields: { [string]: string } = {}

  for line in text:gmatch("[^\n]+") do
    local key, value = line:match("^(%a[%a_]*)\t(.*)$")
    if key then
      fields[key] = value
    end
  end

  return fields
end

function M.bandLabel(band: string): string
  if band == "auto" then
    return "Auto"
  end
  return band ~= "" and (band .. " GHz") or ""
end

-- monarch-wifi-list prints signal, security, in-use and saved before the name,
-- which is last because it is the only field that may contain a tab.
export type Network = {
  ssid: string,
  signal: number,
  security: string,
  connected: boolean,
  saved: boolean,
}

function M.parseNetworks(text: string): { Network }
  local networks: { Network } = {}

  for line in text:gmatch("[^\n]+") do
    local signal, security, inUse, saved, ssid = line:match("^(%d+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
    if ssid and ssid ~= "" then
      table.insert(networks, {
        ssid = ssid,
        signal = tonumber(signal) or 0,
        security = security,
        connected = inUse == "yes",
        saved = saved == "yes",
      })
    end
  end

  return networks
end

function M.isSecured(network: Network): boolean
  return network.security ~= "" and network.security ~= "open"
end

-- nmcli concatenates the security flags it finds, so an enterprise AP reads
-- "WPA2 802.1X". Plain find, not a pattern: the dot would otherwise match the
-- separator in anything shaped like it.
function M.isEnterprise(network: Network): boolean
  return network.security:find("802.1X", 1, true) ~= nil
end

-- Four bars' worth of resolution is all the glyph set gives, and it is all a
-- percentage from nmcli is worth.
function M.signalGlyph(signal: number): string
  if signal >= 75 then
    return "wifi"
  elseif signal >= 50 then
    return "wifi-2"
  elseif signal >= 25 then
    return "wifi-1"
  end
  return "wifi-0"
end

return M
