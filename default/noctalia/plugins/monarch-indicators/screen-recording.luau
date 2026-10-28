--!strict
-- Shows the recording glyph while gpu-screen-recorder runs; hidden otherwise.
-- Ports the v4 CustomButton whose leftClickExec stopped the recording.

local indicator = require("./indicator.luau")

local COMMAND = indicator.bin("monarch-capture-screenrecording")
local checking = false
local refreshPending = false

barWidget.setVisible(false)
noctalia.setUpdateInterval(30000)

function update()
  if checking then
    refreshPending = true
    return
  end
  checking = true
  local started = noctalia.runAsync(COMMAND .. " --status", function(result)
    checking = false
    if result.exitCode == 0 then
      barWidget.setText("󰻂")
      barWidget.setColor("error")
      barWidget.setTooltip("Stop recording")
      barWidget.setVisible(true)
    else
      barWidget.clearTooltip()
      barWidget.setVisible(false)
    end
    if refreshPending then
      refreshPending = false
      update()
    end
  end)
  if not started then
    checking = false
  end
end

function onIpc(event)
  if event == "refresh" then
    update()
  end
end

update()

-- monarch-capture-screenrecording toggles: it stops whenever a recording is
-- already running, so no --stop-recording flag is needed here.
function onClick()
  noctalia.runAsync(COMMAND, function()
    update()
  end)
end
