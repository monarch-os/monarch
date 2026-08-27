--!nonstrict
-- The connected Wi-Fi network as a QR code, with the password behind one
-- deliberate click. Port of quattro's omarchy.wifiqr, which draws the code with
-- Quickshell rectangles; v5's plugin UI has no shape primitive, so the code
-- arrives as a PNG from monarch-wifi-qr and is shown with ui.image.
--
-- Noctalia is started by the compositor with only /usr/*bin on PATH, so Monarch
-- commands go through a shell that prepends Monarch's bin.

local HOME = noctalia.getenv("HOME") or ""
local MONARCH_BIN = "/usr/bin"

local IMAGE_SIZE = 320
local TEXT_WIDTH = 320

local ssid = ""
local iface = ""
local security = ""
local imagePath = ""
local errorText = ""
local password = ""
local passwordVisible = false
local passwordError = ""

-- Every generation and reveal takes a ticket: an in-flight run from a previous
-- open must not land on the new card, or it would reveal the previous network's
-- password under this one's name.
local generation = 0
local reveal = 0

local function shellQuote(text: string): string
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function monarchShell(command: string): string
  return "bash -c " .. shellQuote("export PATH=" .. MONARCH_BIN .. ':"$PATH"\n' .. command)
end

local function trim(text: string): string
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The meta line is the first line; the SSID after it may contain anything.
local function firstLine(text: string): string
  return text:match("^[^\n]*") or ""
end

-- stderr if the command left any, the fallback otherwise.
local function errorFrom(result, fallback: string): string
  local message = trim(result and result.stderr or "")
  return message ~= "" and message or fallback
end

local function isSecured(): boolean
  return security ~= "" and security ~= "nopass"
end

local render

local function generate()
  generation += 1
  local ticket = generation

  ssid, iface, security, imagePath, errorText = "", "", "", "", ""
  -- A card being regenerated is a different card: drop the secret with it.
  password, passwordVisible, passwordError = "", false, ""
  reveal += 1
  render()

  noctalia.runAsync(monarchShell("monarch-wifi-qr --png"), function(result)
    if ticket ~= generation then
      return
    end

    if not result or result.exitCode ~= 0 then
      errorText = errorFrom(result, "Could not generate the Wi-Fi QR code")
      render()
      return
    end

    -- meta<TAB>interface<TAB>security<TAB>png<TAB>ssid: the name goes last, it is
    -- the only field that may contain a tab.
    local device, kind, png, name =
      firstLine(result.stdout or ""):match("^meta\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")

    if not png or png == "" then
      errorText = "Could not read the Wi-Fi QR code"
      render()
      return
    end

    iface = device
    security = kind
    imagePath = png
    ssid = name
    render()
  end)
end

local function revealPassword()
  reveal += 1
  local ticket = reveal
  passwordError = ""

  noctalia.runAsync(monarchShell("monarch-wifi-password " .. shellQuote(iface)), function(result)
    if ticket ~= reveal then
      return
    end

    if not result or result.exitCode ~= 0 then
      passwordError = errorFrom(result, "Could not read the Wi-Fi password")
      render()
      return
    end

    password = trim(result.stdout or "")
    passwordVisible = password ~= ""
    if not passwordVisible then
      passwordError = "Could not read the Wi-Fi password"
    end
    render()
  end)
end

function render()
  local body = {}

  if errorText ~= "" then
    table.insert(body, ui.label({ text = errorText, color = "error", maxWidth = TEXT_WIDTH, textAlign = "center" }))
  elseif imagePath == "" then
    table.insert(body, ui.label({ text = "Generating the QR code…", color = "on_surface_variant" }))
  else
    -- No radius: qrencode bakes the spec quiet zone into an opaque white plate,
    -- and rounding it would eat into that zone.
    table.insert(body, ui.image({ path = imagePath, width = IMAGE_SIZE, height = IMAGE_SIZE }))
    table.insert(body, ui.label({
      text = "Scan to join this network",
      fontSize = 12,
      color = "on_surface_variant",
    }))

    if isSecured() then
      if passwordError ~= "" then
        table.insert(body, ui.label({
          text = passwordError,
          color = "error",
          maxWidth = TEXT_WIDTH,
          textAlign = "center",
        }))
      elseif passwordVisible then
        table.insert(body, ui.label({ text = password, maxWidth = TEXT_WIDTH, textAlign = "center" }))
      else
        table.insert(body, ui.button({ text = "Show password", glyph = "eye", onClick = "onPasswordClicked" }))
      end
    end
  end

  panel.render(ui.column({ flexGrow = 1, gap = 12 }, {
    ui.row({ align = "center", gap = 8 }, {
      ui.label({
        text = ssid ~= "" and ssid or "Wi-Fi",
        fontSize = 15,
        fontWeight = "bold",
        color = "on_surface",
        maxLines = 1,
        flexGrow = 1,
      }),
      ui.button({ glyph = "close", onClick = "onCloseClicked" }),
    }),

    ui.column({ flexGrow = 1, gap = 12, align = "center", justify = "center" }, body),
  }))
end

-- Every open regenerates: the card is only right about the connection the
-- machine is on at the moment it is summoned.
function onOpen(_context)
  generate()
end

function onClose()
  -- The PNG on disk is pruned by the next generation, which is what keeps only
  -- one of them around.
  generation += 1
  reveal += 1
  password = ""
  passwordVisible = false
  imagePath = ""
end

function onPasswordClicked()
  if passwordVisible or iface == "" then
    return
  end
  revealPassword()
end

function onCloseClicked()
  panel.close()
end

function onKey(chord, pressed)
  if pressed and chord == "escape" then
    panel.close()
  end
end
