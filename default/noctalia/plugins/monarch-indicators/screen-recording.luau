--!strict
-- Shows "● REC" while gpu-screen-recorder runs; hidden otherwise.
-- Ports the v4 CustomButton whose leftClickExec stopped the recording.

local indicator = require("./indicator.luau")

indicator.stream("screen-recording.sh")

-- monarch-capture-screenrecording toggles: it stops whenever a recording is
-- already running, so no --stop-recording flag is needed here.
function onClick()
  noctalia.runAsync(indicator.bin("monarch-capture-screenrecording"))
end
