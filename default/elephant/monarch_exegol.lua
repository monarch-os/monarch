--
-- Dynamic Exegol Container Menu for Elephant/Walker
-- Lists exegol containers with live info preview panel
--
Name = "monarchExegol"
NamePretty = "Exegol"
Cache = false
HideFromProviderlist = true
FixedOrder = true

local function ShellEscape(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Fetch container details via monarch-menu-exegol info
local function GetContainerInfo(short_name)
  local handle = io.popen("monarch-menu-exegol info " .. ShellEscape(short_name) .. " 2>/dev/null")
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
    Preview = "Create a new Exegol container.\n\nYou will be guided through:\n  - Image selection\n  - Container name\n  - VPN configuration (optional)\n  - Shell logging (optional)",
    PreviewType = "text",
    Actions = {
      ["menus:default"] = "setsid -f monarch-menu-exegol create",
    },
  })

  -- List exegol containers via docker
  local handle = io.popen("docker ps -a -f 'name=exegol' --format '{{.Names}}|{{.State}}|{{.Image}}|{{.Status}}' 2>/dev/null")
  if not handle then
    return entries
  end

  for line in handle:lines() do
    local name, state, image, status = line:match("([^|]+)|([^|]+)|([^|]+)|(.+)")
    if name then
      local short_name = name:gsub("^exegol%-", "")
      local short_image = image:match(":(.+)$") or image:gsub(".*/", "")

      local icon
      if state == "running" then
        icon = "🟢"
      else
        icon = "🔴"
      end

      local default_action
      if state == "running" then
        default_action = "monarch-menu-exegol shell " .. ShellEscape(short_name)
      else
        default_action = "monarch-menu-exegol start " .. ShellEscape(short_name)
      end

      -- Pre-fetch container info for preview
      local preview = GetContainerInfo(short_name) or ("Container: " .. short_name)

      table.insert(entries, {
        Text = icon .. " " .. short_name,
        Subtext = short_image,
        Value = short_name,
        Preview = preview,
        PreviewType = "text",
        Actions = {
          ["menus:default"] = default_action,
          ["stop"] = "monarch-menu-exegol stop " .. ShellEscape(short_name),
          ["remove"] = "monarch-menu-exegol remove " .. ShellEscape(short_name),
          ["workspace"] = "monarch-menu-exegol workspace " .. ShellEscape(short_name),
          ["firefox"] = "monarch-menu-exegol firefox " .. ShellEscape(short_name),
          ["bloodhound"] = "monarch-menu-exegol bloodhound " .. ShellEscape(short_name),
        },
      })
    end
  end

  handle:close()
  return entries
end
