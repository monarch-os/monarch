--!nonstrict

local root = "/usr/share/monarch"
local crashes = {}
local selected = nil
local status = ""
local loading = false
local agentAvailable = false
local requested = ""
local page = 1
local more = false
local generation = 0
local render
local pageSize = 6
local coreLabels = {
  present = "Dump disponible",
  truncated = "Dump partiel",
  missing = "Dump supprimé ou inaccessible",
  unavailable = "Sans dump mémoire",
}

local function label(text, size, color)
  return ui.label({ text = text, fontSize = size or 13,
    color = color or "on_surface", maxLines = 4 })
end

local function load()
  if selected then return end
  generation += 1
  local request = generation
  loading = true
  status = ""
  render()
  noctalia.runAsync({ "/usr/bin/env", "MONARCH_PATH=" .. root,
    root .. "/bin/monarch-crash-history", "list", "--json" }, function(result)
    if request ~= generation then return end
    loading = false
    local data = result and result.exitCode == 0 and noctalia.json.decode(result.stdout or "") or nil
    if type(data) ~= "table" or type(data.crashes) ~= "table" then
      crashes = {}
      status = "L’historique n’a pas pu être chargé."
      render()
      return
    end
    crashes = data.crashes
    more = data.hasMore == true
    page = 1
    if requested ~= "" then
      local id = requested
      requested = ""
      for _, crash in crashes do
        if crash.id == id then selected = crash; break end
      end
      if not selected then
        loading = true
        noctalia.runAsync({ "/usr/bin/env", "MONARCH_PATH=" .. root,
          root .. "/bin/monarch-crash-history", "show", id, "--json" }, function(detail)
          if request ~= generation then return end
          loading = false
          local crash = detail and detail.exitCode == 0 and noctalia.json.decode(detail.stdout or "") or nil
          if type(crash) == "table" and crash.id == id then selected = crash
          else status = "Le crash demandé n’est plus disponible." end
          render()
        end)
      end
    end
    render()
  end)
end

local function openReport(analyze)
  if loading or not selected or (analyze and not agentAvailable) then return end
  local argv = { "/usr/bin/env", "MONARCH_PATH=" .. root, root .. "/bin/monarch-crash-report", selected.id }
  if analyze then table.insert(argv, "--analyze") end
  if noctalia.runAsync(argv) then panel.close()
  else status = "La fenêtre de rapport n’a pas pu démarrer."; render() end
end

function render()
  local children = {
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = "Crashes", fontSize = 15, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
      ui.button({ text = "Actualiser", variant = "ghost", height = 30, enabled = not loading and not selected, onClick = load }),
      ui.button({ glyph = "close", onClick = function() panel.close() end }),
    }),
  }
  local body = {}
  if selected then
    body = {
      label(selected.application, 21),
      label(selected.date .. " · " .. selected.signal, 12, "on_surface/0.7"),
      label(coreLabels[selected.core] or coreLabels.unavailable, 13),
      label("Préparez un rapport, examinez les pièces proposées et masquez les informations privées avant l’envoi.", 13),
      label("Rien n’est envoyé à Monarch sans votre confirmation. Le core brut reste sur la machine.", 12, "on_surface/0.7"),
    }
  elseif loading then
    body = { label("Chargement des crashes…") }
  elseif #crashes == 0 then
    body = { label("Aucun crash enregistré", 21) }
  else
    for i = (page - 1) * pageSize + 1, math.min(page * pageSize, #crashes) do
      local crash = crashes[i]
      table.insert(body, ui.row({ key = crash.id, padding = 8, gap = 10, align = "center" }, {
        ui.column({ gap = 2, flexGrow = 1 }, {
          label(crash.application, 14), label(crash.date .. " · " .. crash.signal, 11, "on_surface/0.65"),
        }),
        ui.button({ text = "Détails", height = 30, variant = "outline",
          onClick = function() selected = crash; status = ""; render() end }),
      }))
    end
  end
  table.insert(children, ui.scroll({ flexGrow = 1, gap = 8, align = "stretch" }, body))
  if status ~= "" then table.insert(children, label(status, 12, "error")) end
  if selected then
    local buttons = {
      ui.button({ text = "Retour", height = 32, variant = "ghost", onClick = onBackClicked }),
    }
    if agentAvailable then
      table.insert(buttons, ui.button({ text = "Analyser avec l’IA", height = 32, variant = "outline",
        onClick = function() openReport(true) end }))
    end
    table.insert(buttons, ui.spacer({ flexGrow = 1 }))
    table.insert(buttons, ui.button({ text = "Envoyer un rapport", height = 32, variant = "primary",
      onClick = function() openReport(false) end }))
    table.insert(children, ui.row({ gap = 8 }, buttons))
  else
    local pages = math.max(1, math.ceil(#crashes / pageSize))
    table.insert(children, ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = tostring(#crashes) .. (more and "+" or "") .. " crashes · " .. tostring(page) .. " / " .. tostring(pages),
        fontSize = 11, color = "on_surface/0.55", flexGrow = 1 }),
      ui.button({ text = "Précédent", height = 30, enabled = page > 1, onClick = function() page -= 1; render() end }),
      ui.button({ text = "Suivant", height = 30, enabled = page < pages, onClick = function() page += 1; render() end }),
    }))
  end
  panel.render(ui.column({ flexGrow = 1, gap = 8 }, children))
end

function onOpen(context)
  local data = noctalia.json.decode(context or "")
  root = type(data) == "table" and type(data.root) == "string" and data.root
    or noctalia.getenv("MONARCH_PATH") or "/usr/share/monarch"
  requested = type(data) == "table" and type(data.id) == "string" and data.id or ""
  agentAvailable = type(data) == "table" and data.agent == true
  selected = nil
  load()
end

function onClose()
  generation += 1
  loading = false
end

function onBackClicked()
  generation += 1
  loading = false
  status = ""
  selected = nil
  render()
end

function onKey(chord, pressed)
  if pressed and chord == "left" then onBackClicked() end
end

function onIpc(event)
  if event == "refresh" then load()
  elseif event == "preview" then openReport(false)
  elseif event == "back" then onBackClicked() end
end
