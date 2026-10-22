--!strict
local M = {}

function M.start(name, glyph, tooltip)
  local runtime = noctalia.getenv("XDG_RUNTIME_DIR")
  if not runtime or runtime == "" then
    -- Match the command's /run/user/$(id -u) fallback without spawning id.
    local uid = nil
    local status = noctalia.readFile("/proc/self/status")
    if status then
      uid = status:match("\nUid:%s+(%d+)")
    end
    if not uid then
      barWidget.setVisible(false)
      noctalia.log("runtime toggle: cannot determine the session runtime directory")
      return function() end
    end
    runtime = "/run/user/" .. uid
  end

  local path = runtime .. "/monarch/" .. name
  local function refresh()
    local info = noctalia.fileInfo(path)
    if info and not info.isDir then
      barWidget.setText(glyph)
      barWidget.setColor("primary")
      barWidget.setTooltip(tooltip)
      barWidget.setVisible(true)
    else
      barWidget.clearTooltip()
      barWidget.setVisible(false)
    end
  end

  -- Recover missed events, direct marker edits and reloads without subprocesses.
  noctalia.setUpdateInterval(30000)
  refresh()
  return refresh
end

return M
