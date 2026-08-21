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

-- stderr if the command left any, the fallback otherwise. First line only: this
-- lands on a network row, and nmcli's multi-line failures would push the list off.
function M.errorFrom(result, fallback: string): string
  local message = M.trim(result and result.stderr or ""):match("^[^\n]*") or ""
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

-- Quattro's order. The name breaks ties so a re-render cannot shuffle
-- equal-signal rows: table.sort is not stable.
function M.sortNetworks(networks: { Network }): { Network }
  local sorted = table.move(networks, 1, #networks, 1, {})

  table.sort(sorted, function(a, b)
    if a.connected ~= b.connected then
      return a.connected
    elseif a.saved ~= b.saved then
      return a.saved
    elseif a.signal ~= b.signal then
      return a.signal > b.signal
    end
    return a.ssid < b.ssid
  end)

  return sorted
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

-- Tabler's Wi-Fi ramp is five filled arcs, not four: `wifi-3` sits between
-- `wifi-2` and the full `wifi`, and skipping it made the middle of the scale
-- jump. Five steps in twenties is also exactly what quattro draws, over the
-- five Nerd Font glyphs its own shell has.
local SIGNAL = { "wifi-0", "wifi-1", "wifi-2", "wifi-3", "wifi" }

function M.signalGlyph(signal: number): string
  return SIGNAL[math.max(1, math.min(#SIGNAL, math.ceil(signal / 20)))]
end

return M
