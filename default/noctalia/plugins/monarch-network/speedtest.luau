--!nonstrict
-- Live download and upload, one second per sample, on the interface counters.
-- Its own panel for the same reason it is one upstream: the network panel is
-- already long, and a speed test is something you summon, watch, and dismiss.

local shared = require("./shared.luau")

local SPEEDTEST_CMD = shared.bin("monarch-network-speedtest")
local SECONDS = 10

local direction = ""
local samples = {}
local peak = 0
local finished = false
local errorText = ""

-- monarch-network-speedtest stops on its own after SECONDS, which is what makes
-- this safe: runStream hands back no handle to cancel with, so a run that only
-- ended when told to would outlive the panel.
local generation = 0

local render

local function start(which: string)
  generation += 1
  local ticket = generation

  direction = which
  samples = {}
  peak = 0
  finished = false
  errorText = ""
  render()

  local started = noctalia.runStream(
    SPEEDTEST_CMD .. " " .. which .. " " .. SECONDS,
    function(line)
      if ticket ~= generation then
        return
      end

      local value = tonumber(shared.trim(line))
      if not value then
        -- Anything that is not a number is the command explaining itself.
        errorText = shared.trim(line)
        finished = true
        render()
        return
      end

      table.insert(samples, value)
      if value > peak then
        peak = value
      end
      if #samples >= SECONDS then
        finished = true
      end
      render()
    end
  )

  if not started then
    errorText = "Could not start the speed test"
    finished = true
    render()
  end
end

local function latest(): number
  return #samples > 0 and samples[#samples] or 0
end

local function formatMbps(value: number): string
  return value < 10 and string.format("%.1f", value) or string.format("%.0f", value)
end

function render()
  local body = {}

  if direction == "" then
    table.insert(body, ui.label({
      text = "Saturates the link for " .. SECONDS .. " seconds.",
      fontSize = 12,
      color = "on_surface_variant",
      textAlign = "center",
    }))
  else
    table.insert(body, ui.label({
      text = formatMbps(latest()) .. " Mb/s",
      fontSize = 28,
      fontWeight = "bold",
      color = finished and "on_surface" or "primary",
    }))
    table.insert(body, ui.label({
      text = (direction == "down" and "Download" or "Upload")
        .. (finished and " — peak " .. formatMbps(peak) .. " Mb/s" or "…"),
      fontSize = 12,
      color = "on_surface_variant",
    }))
    -- Against the run's own peak, so the bar fills regardless of the link's
    -- speed; there is no meaningful absolute maximum to scale to.
    table.insert(body, ui.progress({
      value = peak > 0 and latest() / peak or 0,
      width = 260,
    }))
  end

  if errorText ~= "" then
    table.insert(body, ui.label({ text = errorText, fontSize = 12, color = "error", textAlign = "center" }))
  end

  local running = direction ~= "" and not finished

  panel.render(ui.column({ flexGrow = 1, gap = 12 }, {
    ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = "Speed test", fontSize = 15, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
      ui.button({ glyph = "close", onClick = "onCloseClicked" }),
    }),

    ui.column({ flexGrow = 1, gap = 10, align = "center", justify = "center" }, body),

    ui.row({ gap = 8, align = "center", justify = "center" }, {
      ui.button({
        text = "Download",
        variant = direction == "down" and "primary" or "outline",
        enabled = not running,
        onClick = "onDownClicked",
      }),
      ui.button({
        text = "Upload",
        variant = direction == "up" and "primary" or "outline",
        enabled = not running,
        onClick = "onUpClicked",
      }),
    }),
  }))
end

function onOpen(_context)
  direction = ""
  samples = {}
  peak = 0
  finished = false
  errorText = ""
  render()
end

-- The stream keeps writing until the command exits; bumping the ticket makes a
-- closed panel ignore what is still arriving.
function onClose()
  generation += 1
end

function onCloseClicked()
  panel.close()
end

function onDownClicked()
  start("down")
end

function onUpClicked()
  start("up")
end

function onKey(chord, pressed)
  if pressed and chord == "escape" then
    panel.close()
  end
end
