--!nonstrict

local root = ""
local stateHome = ""
local phase = "welcome"
local shortcuts = {}
local status = ""
local saving = false
local toolsLoaded = false
local toolsLoading = false
local installed = {}
local activeTool = ""
local launching = false
local tick = 0
local tools = {
  { id = "burpsuite", name = "Burp Suite", detail = "Tests web · Community ou Pro" },
  { id = "rfswift", name = "RF Swift", detail = "Environnements pour les tests radio et matériels" },
  { id = "seclists", name = "SecLists", detail = "Listes de mots pour vos tests de sécurité" },
}
local render
local steps = { "shortcuts", "appearance", "software" }
local titles = {
  shortcuts = "Se repérer",
  appearance = "Choisir son style",
  software = "Logiciels et outils cyber",
}

local function quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function run(arguments, callback)
  noctalia.runAsync("MONARCH_PATH=" .. quote(root) .. " XDG_STATE_HOME=" .. quote(stateHome) .. " "
    .. quote(root .. "/bin/monarch-setup-first-steps") .. " " .. arguments, callback)
end

local function change(nextPhase)
  if saving then return end
  saving = true
  run("record " .. quote(nextPhase), function(result)
    saving = false
    if result and result.exitCode == 0 then
      phase = nextPhase
    else
      status = "La progression n’a pas pu être enregistrée."
    end
    render()
  end)
end

local function label(text, size, color)
  return ui.label({ text = text, fontSize = size or 13, color = color or "on_surface", maxLines = 3 })
end

local function entry(number, title, detail)
  return ui.row({ gap = 10, padding = 10, radius = 8, fill = "surface_variant", align = "center" }, {
    ui.label({ text = number, fontSize = 16, color = "primary", width = 22 }),
    ui.column({ gap = 2, flexGrow = 1 }, {
      ui.label({ text = title, fontSize = 13, fontWeight = "bold", color = "on_surface" }),
      label(detail, 11, "on_surface/0.65"),
    }),
  })
end

local function loadTools()
  if toolsLoading then return end
  toolsLoading = true
  run("tools-state", function(result)
    toolsLoading = false
    local state = result and result.exitCode == 0 and noctalia.json.decode(result.stdout) or nil
    if type(state) == "table" then
      installed = state.installed or {}
      activeTool = state.active or ""
      toolsLoaded = true
      if state.lastResult and state.lastResult.code ~= 0 then
        status = "Installation interrompue ou échouée. Consultez le terminal."
      end
    else
      status = "L’état des outils n’a pas pu être chargé."
    end
    render()
  end)
end

local function toolRow(tool)
  local present = installed[tool.id] == true
  local busy = activeTool == tool.id
  local text = busy and "En cours…" or "Installer"
  return ui.row({ key = tool.id, gap = 10, padding = 8, radius = 8, fill = "surface_variant", align = "center" }, {
    ui.column({ flexGrow = 1, gap = 2 }, {
      ui.label({ text = tool.name, fontSize = 13, fontWeight = "bold", color = "on_surface" }),
      label(tool.detail, 11, "on_surface/0.65"),
    }),
    present and ui.label({ text = "✓ Installé", fontSize = 11, color = "primary", width = 72, textAlign = "end" })
      or ui.button({ text = text, height = 30, variant = "outline",
      enabled = toolsLoaded and not present and activeTool == "" and not launching,
      onClick = function() onInstallClicked(tool.id) end,
    }),
  })
end

local function content()
  if phase == "welcome" then
    return {
      label("Bienvenue sur Monarch", 22),
      label("Trois repères pour prendre votre bureau en main.", 13, "on_surface/0.7"),
      entry("01", "Se repérer", "monarch-menu · Win + Alt + Espace"),
      entry("02", "Choisir son style", "Thèmes et fonds d’écran"),
      entry("03", "Logiciels et outils cyber", "Installer vos outils à la carte"),
      label("Retrouvez ce guide dans monarch-menu → Documentation → Premiers pas.", 12, "on_surface/0.65"),
    }
  end
  if phase == "done" then
    return {
      label("À vous de jouer", 22),
      label("Votre bureau est prêt. Explorez-le à votre rythme.", 13, "on_surface/0.7"),
      entry("01", "Le menu toujours à portée de main", "monarch-menu · Win + Alt + Espace"),
      entry("02", "Un style à votre image", "Les thèmes et fonds d’écran sont dans Personalization."),
      entry("03", "Vos outils à portée de main", "Retrouvez les outils de cyber dans Software → Cyber."),
      label("Consultez la documentation pour retrouver les guides du bureau et de Pentest Tools.", 12, "on_surface/0.65"),
    }
  end

  local children = { label(titles[phase], 22) }
  if phase == "shortcuts" then
    table.insert(children, label("Trois raccourcis pour commencer. Super correspond à la touche Windows.", 13, "on_surface/0.7"))
    if #shortcuts == 0 then
      table.insert(children, label("Consultez les raccourcis actifs de votre bureau.", 13))
    else
      for _, binding in shortcuts do
        local name = binding.label == "Monarch menu" and "monarch-menu"
          or binding.label == "Launcher (Noctalia)" and "Lanceur d’applications" or binding.label
        local shortcut = binding.shortcut:gsub("SUPER", "Win"):gsub("ALT", "Alt")
          :gsub("Space", "Espace"):gsub("Return", "Entrée"):gsub("Win Alt", "Win + Alt")
          :gsub("%s*%+%s*", " + ")
        table.insert(children, ui.row({ key = binding.label, padding = 10, gap = 12,
          radius = 8, fill = "surface_variant", align = "center" }, {
          ui.label({ text = name, fontSize = 13, color = "on_surface", flexGrow = 1 }),
          ui.label({ text = shortcut, fontSize = 12, color = "primary", maxLines = 1 }),
        }))
      end
    end
    table.insert(children, ui.button({ text = "Voir tous les raccourcis", height = 32, fontSize = 12, onClick = "onVisitClicked" }))
  elseif phase == "appearance" then
    table.insert(children, label("Choisissez une palette et un fond d’écran qui vous ressemblent.", 13, "on_surface/0.7"))
    table.insert(children, entry("◐", "Thèmes", "Une palette partagée entre le bureau et vos applications."))
    table.insert(children, entry("▧", "Fonds d’écran", "Retrouvez-les dans Personalization → Backgrounds."))
    table.insert(children, ui.button({ text = "Explorer les thèmes", height = 32, fontSize = 12, onClick = "onVisitClicked" }))
  elseif phase == "software" then
    table.insert(children, label("Caido et Exegol sont inclus. Installez vos logiciels et outils à la carte.", 13, "on_surface/0.75"))
    for _, tool in tools do table.insert(children, toolRow(tool)) end
    table.insert(children, ui.row({ gap = 8, padding = 0, fill = "surface/0" }, {
      ui.button({ text = "Installer des logiciels", height = 32, fontSize = 12, onClick = "onVisitClicked" }),
      ui.button({ text = "Catalogue Cyber", height = 32, fontSize = 12, variant = "outline", onClick = "onCyberClicked" }),
    }))
    table.insert(children, label("Les installations s’ouvrent dans un terminal pour suivre leur progression.", 11, "on_surface/0.55"))
  end
  if phase ~= "software" then
    table.insert(children, label("Fermez le panneau exploré pour revenir à cette étape.", 11, "on_surface/0.55"))
  end
  return children
end

function render()
  local index = table.find(steps, phase)
  local buttons
  if phase == "welcome" then
    buttons = {
      ui.button({ text = "Passer", height = 36, variant = "ghost", onClick = "onSkipClicked" }),
      ui.spacer({ flexGrow = 1 }),
      ui.button({ text = "Découvrir Monarch", height = 36, variant = "primary", onClick = "onNextClicked" }),
    }
  elseif phase == "done" then
    buttons = {
      ui.button({ text = "Refaire la visite", height = 36, onClick = function() change("welcome") end }),
      ui.spacer({ flexGrow = 1 }),
      ui.button({ text = "C’est parti", height = 36, variant = "primary", onClick = "onCloseClicked" }),
    }
  else
    buttons = {
      ui.button({ text = "Retour", height = 36, onClick = "onBackClicked" }),
      ui.spacer({ flexGrow = 1 }),
      ui.button({ text = index == 3 and "Terminer" or "Continuer", height = 36, variant = "primary", onClick = "onNextClicked" }),
    }
  end
  local children = {
    ui.row({ align = "center", gap = 10 }, {
      ui.label({ text = "Premiers pas", fontSize = 14, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
      label(index and tostring(index) .. " / 3" or "", 11, "on_surface/0.55"),
      ui.button({ glyph = "close", onClick = "onCloseClicked" }),
    }),
    ui.scroll({ flexGrow = 1, gap = 8, align = "stretch" }, content()),
  }
  if status ~= "" then table.insert(children, label(status, 11, "on_surface/0.65")) end
  table.insert(children,
    ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = "monarch-menu · Win + Alt + Espace", fontSize = 11, color = "on_surface/0.65", flexGrow = 1 }),
      ui.button({ text = "Documentation", variant = "ghost", height = 32, onClick = function() onDocsClicked() end }),
    })
  )
  table.insert(children, ui.row({ gap = 8, align = "center" }, buttons))
  panel.render(ui.column({ flexGrow = 1, gap = 10 }, children))
end

function onOpen(context)
  local request = noctalia.json.decode(context or "")
  if type(request) ~= "table" or type(request.root) ~= "string"
    or type(request.stateHome) ~= "string" then
    panel.close()
    return
  end
  root = request.root
  stateHome = request.stateHome
  phase = request.phase or "welcome"
  if not table.find(steps, phase) and phase ~= "done" then phase = "welcome" end
  status = ""
  tick = 0
  panel.setWantsSecondTicks(true)
  loadTools()
  shortcuts = {}
  noctalia.runAsync(quote(root .. "/bin/monarch-menu-keybindings") .. " --json", function(result)
    local bindings = result and result.exitCode == 0 and noctalia.json.decode(result.stdout) or nil
    if type(bindings) == "table" then
      for _, binding in bindings do
        if binding.label == "Terminal" or binding.label == "Launcher (Noctalia)"
          or binding.label == "Monarch menu" then
          table.insert(shortcuts, binding)
        end
      end
    end
    render()
  end)
  render()
  run("opened")
end

function onNextClicked()
  local index = table.find(steps, phase)
  change(index and (steps[index + 1] or "done") or "shortcuts")
end

function onBackClicked()
  local index = table.find(steps, phase)
  change(index and steps[index - 1] or "welcome")
end

function onSkipClicked()
  panel.close()
end

function onCloseClicked()
  panel.close()
end

function onVisitClicked()
  run("visit " .. quote(phase))
end

function onCyberClicked()
  run("visit cyber")
end

function onDocsClicked()
  run("docs")
end

function onInstallClicked(tool)
  if not toolsLoaded or launching or activeTool ~= "" or installed[tool] then return end
  launching = true
  render()
  run("install-tool " .. quote(tool), function(result)
    launching = false
    status = result and result.exitCode == 0 and "Installation ouverte dans un terminal." or "L’installation n’a pas pu être lancée."
    loadTools()
    render()
  end)
end

function update()
  tick += 1
  if phase == "software" and tick % 3 == 0 then loadTools() end
end

function onKey(chord, pressed)
  if not pressed then return end
  if chord == "return" or chord == "right" then
    if phase ~= "done" then onNextClicked() end
  elseif chord == "left" then onBackClicked() end
end

function onIpc(event)
  if event == "next" then onNextClicked()
  elseif event == "back" then onBackClicked()
  elseif event == "skip" then onSkipClicked()
  elseif event == "visit" then onVisitClicked()
  elseif event == "visit-cyber" then onCyberClicked() end
end
