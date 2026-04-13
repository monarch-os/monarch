--
-- Dynamic RF Swift Container Menu for Elephant/Walker
-- Lists rfswift containers with live info preview panel
--
Name = "monarchRFSwift"
NamePretty = "RF Swift"
Cache = false
HideFromProviderlist = true
FixedOrder = true

local function ShellEscape(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Fetch container details via monarch-menu-rfswift info
local function GetContainerInfo(name)
  local handle = io.popen("monarch-menu-rfswift info " .. ShellEscape(name) .. " 2>/dev/null")
  if not handle then
    return nil
  end
  local info = handle:read("*a")
  handle:close()
  if not info or info == "" then
    return nil
  end
  return info
end

function GetEntries()
  local entries = {}

  -- "Create workspace" entry at the top
  table.insert(entries, {
    Text = "  Create workspace",
    Preview = "Create a new RF Swift container.\n\nYou will be guided through:\n  - Image selection\n  - Container name\n  - VPN configuration (optional)\n  - Session recording (optional)\n  - Desktop mode (optional)",
    PreviewType = "text",
    Actions = {
      ["menus:default"] = "setsid -f monarch-menu-rfswift create",
    },
  })

  -- List rfswift containers via docker (filter by image — rfswift uses no name prefix)
  local handle = io.popen("docker ps -a --format '{{.Names}}|{{.State}}|{{.Image}}|{{.Status}}' 2>/dev/null")
  if not handle then
    return entries
  end

  for line in handle:lines() do
    local name, state, image, status = line:match("([^|]+)|([^|]+)|([^|]+)|(.+)")
    if name and image:find("penthertz/rfswift") then
      local short_image = image:match(":(.+)$") or image:gsub(".*/", "")

      local icon
      if state == "running" then
        icon = "🟢"
      else
        icon = "🔴"
      end

      local default_action
      if state == "running" then
        default_action = "monarch-menu-rfswift shell " .. ShellEscape(name)
      else
        default_action = "monarch-menu-rfswift start " .. ShellEscape(name)
      end

      local preview = GetContainerInfo(name) or ("Container: " .. name)

      table.insert(entries, {
        Text = icon .. " " .. name,
        Subtext = short_image,
        Value = name,
        Preview = preview,
        PreviewType = "text",
        Actions = {
          ["menus:default"] = default_action,
          ["stop"] = "monarch-menu-rfswift stop " .. ShellEscape(name),
          ["remove"] = "monarch-menu-rfswift remove " .. ShellEscape(name),
          ["workspace"] = "monarch-menu-rfswift workspace " .. ShellEscape(name),
        },
      })
    end
  end

  handle:close()
  return entries
end
