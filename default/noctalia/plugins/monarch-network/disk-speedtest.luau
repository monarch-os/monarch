--!nonstrict

local shared = require("./shared.luau")

local COMMAND = shared.bin("monarch-disk-speedtest")
local disk = "Disk"
local phase = ""
local readRate = 0
local writeRate = 0
local peak = 0
local running = false
local finished = false
local errorText = ""
local generation = 0

local render

local function formatRate(value: number): string
  return value < 10 and string.format("%.1f MB/s", value) or string.format("%.0f MB/s", value)
end

local function start()
  generation += 1
  local ticket = generation

  disk = "Disk"
  phase = "Preparing"
  readRate = 0
  writeRate = 0
  peak = 0
  running = true
  finished = false
  errorText = ""
  render()

  local started = noctalia.runStream(COMMAND, function(line)
    if ticket ~= generation then
      return
    end

    local output = shared.trim(line)
    local kind, value = output:match("^(%S+)%s+(.+)$")
    local rate = tonumber(value or "")
    if output == "done" then
      phase = ""
      running = false
      finished = true
    elseif kind == "disk" then
      disk = value
    elseif (kind == "read" or kind == "write") and rate then
      phase = kind == "read" and "Reading" or "Writing"
      if kind == "read" then
        readRate = rate
      else
        writeRate = rate
      end
      peak = math.max(peak, rate)
    else
      errorText = shared.trim(line)
      running = false
    end
    render()
  end)

  if not started then
    errorText = "Could not start the disk speed test"
    running = false
    render()
  end
end

local function metric(label: string, value: number, active: boolean)
  return ui.column({ flexGrow = 1, gap = 4, align = "center" }, {
    ui.label({
      text = formatRate(value),
      fontSize = 22,
      fontWeight = "bold",
      color = active and "primary" or "on_surface",
    }),
    ui.label({ text = label, fontSize = 12, color = "on_surface_variant" }),
    ui.progress({ value = peak > 0 and value / peak or 0, width = 140 }),
  })
end

function render()
  panel.render(ui.column({ flexGrow = 1, gap = 14 }, {
    ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = "Disk speed test", fontSize = 15, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
      ui.button({ glyph = "close", onClick = "onCloseClicked" }),
    }),
    ui.column({ flexGrow = 1, gap = 14, align = "center", justify = "center" }, {
      ui.label({ text = disk, fontSize = 12, color = "on_surface_variant", textAlign = "center" }),
      ui.row({ gap = 18, align = "center", justify = "center" }, {
        metric("Read", readRate, phase == "Reading"),
        metric("Write", writeRate, phase == "Writing"),
      }),
      ui.label({
        text = errorText ~= "" and errorText or (running and phase .. "…" or (finished and "Complete" or "Uses about 1 GB of temporary space.")),
        fontSize = 12,
        color = errorText ~= "" and "error" or "on_surface_variant",
        textAlign = "center",
      }),
    }),
    ui.row({ align = "center", justify = "center" }, {
      ui.button({ text = running and "Running…" or "Run test", variant = "primary", enabled = not running, onClick = "onRunClicked" }),
    }),
  }))
end

function onOpen(_context)
  disk = "Disk"
  phase = ""
  readRate = 0
  writeRate = 0
  peak = 0
  running = false
  finished = false
  errorText = ""
  render()
end

function onClose()
  generation += 1
end

function onCloseClicked()
  panel.close()
end

function onRunClicked()
  start()
end

function onKey(chord, pressed)
  if pressed and chord == "escape" then
    panel.close()
  end
end
