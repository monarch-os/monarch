--!strict
-- Dictation glyph tracking Voxtype's state (idle / recording / transcribing).
-- The script resolves the glyph itself and stays silent when voxtype is not
-- installed, so this entry only wires the two click actions the v4
-- CustomButton carried as leftClickExec / rightClickExec.

local indicator = require("./indicator.luau")

indicator.stream("voxtype.sh")

function onClick()
  noctalia.runAsync(indicator.bin("monarch-voxtype-model"))
end

function onRightClick()
  noctalia.runAsync(indicator.bin("monarch-voxtype-config"))
end
