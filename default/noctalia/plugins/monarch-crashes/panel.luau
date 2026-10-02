--!nonstrict

local root = "/usr/share/monarch"
local crashes = {}
local selected = nil
local report = nil
local status = ""
local loading = false
local exporting = false
local sending = false
local confirming = false
local receipt = ""
local collection = nil
local statusOk = false
local requested = ""
local page = 1
local more = false
local generation = 0
local saved = ""
local render
local pageSize = 6
local coreLabels = {
  present = "Dump disponible",
  truncated = "Dump partiel",
  missing = "Dump supprimé ou inaccessible",
  unavailable = "Sans dump mémoire",
}

local function quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function run(arguments, callback, input)
  local command = "MONARCH_PATH=" .. quote(root) .. " "
    .. quote(root .. "/bin/monarch-crash-history") .. " " .. arguments
  if input then command = "printf '%s' " .. quote(input) .. " | " .. command end
  noctalia.runAsync(command, callback)
end

local function submit(arguments, callback)
  noctalia.runAsync("MONARCH_PATH=" .. quote(root) .. " "
    .. quote(root .. "/bin/monarch-crash-submit") .. " " .. arguments, callback)
end

local function label(text, size, color, lines)
  return ui.label({ text = text, fontSize = size or 13,
    color = color or "on_surface", maxLines = lines or 3 })
end

local function failure(result, fallback)
  local error = result and result.stderr or ""
  return error:match("[^\n]+") or fallback
end

local function load()
  if selected or exporting or sending then return end
  generation += 1
  local request = generation
  loading = true
  status = ""
  render()
  run("list --json", function(result)
    if request ~= generation then return end
    loading = false
    local data = result and result.exitCode == 0 and noctalia.json.decode(result.stdout or "") or nil
    if type(data) == "table" and type(data.crashes) == "table" then
      crashes = data.crashes
      more = data.hasMore == true
      page = 1
      if requested ~= "" then
        for _, crash in crashes do
          if crash.id == requested then selected = crash; break end
        end
        requested = ""
      end
    else
      crashes = {}
      status = failure(result, "L’historique n’a pas pu être chargé.")
    end
    render()
  end)
end

local function choose(crash)
  selected = crash
  report = nil
  saved = ""
  status = ""
  statusOk = false
  receipt = ""
  collection = nil
  confirming = false
  render()
end

local function preview()
  if loading or exporting or sending or report or not selected then return end
  generation += 1
  local request = generation
  loading = true
  status = ""
  render()
  submit("prepare " .. quote(selected.id), function(result)
    if request ~= generation then return end
    loading = false
    local data = result and result.exitCode == 0 and noctalia.json.decode(result.stdout or "") or nil
    if type(data) == "table" and type(data.text) == "string" then
      report = data.text
      receipt = type(data.receipt) == "string" and data.receipt or ""
      collection = nil
      if receipt == "" then
        submit("status", function(response)
          if request ~= generation then return end
          local service = response and response.exitCode == 0 and noctalia.json.decode(response.stdout or "") or nil
          collection = type(service) == "table" and service or { enabled = false, endpoint = "" }
          render()
        end)
      end
    else
      status = failure(result, "Le rapport n’a pas pu être préparé.")
    end
    render()
  end)
end

local function export()
  if exporting or sending or confirming or not selected or not report then return end
  local request = generation
  exporting = true
  render()
  run("export " .. quote(selected.id) .. " --stdin", function(result)
    if request ~= generation then return end
    exporting = false
    local data = result and result.exitCode == 0 and noctalia.json.decode(result.stdout or "") or nil
    if type(data) == "table" and type(data.path) == "string" then
      saved = data.path
      status = "Rapport enregistré. Vous pouvez le joindre à un signalement."
      statusOk = true
    else
      status = failure(result, "Le rapport n’a pas pu être enregistré.")
      statusOk = false
    end
    render()
  end, report)
end

local function send()
  if sending or not confirming or not selected or not report or receipt ~= ""
    or not collection or not collection.enabled then return end
  local request = generation
  sending = true
  status = ""
  render()
  submit("send " .. quote(selected.id) .. " --confirm", function(result)
    if request ~= generation then return end
    sending = false
    local data = result and result.exitCode == 0 and noctalia.json.decode(result.stdout or "") or nil
    if type(data) == "table" and type(data.reference) == "string" and type(data.url) == "string" then
      receipt = data.reference
      confirming = false
      status = "Rapport reçu. Copiez son lien pour votre ticket GitHub."
      statusOk = true
    else
      status = failure(result, "L’envoi a échoué. Vous pouvez réessayer.")
      statusOk = false
    end
    render()
  end)
end

local function copyLink()
  if receipt == "" or not selected then return end
  local request = generation
  submit("copy " .. quote(selected.id), function(result)
    if request ~= generation then return end
    statusOk = result and result.exitCode == 0 or false
    status = statusOk and "Lien copié. La consultation est réservée aux mainteneurs."
      or failure(result, "Le lien n’a pas pu être copié.")
    render()
  end)
end

local function row(crash)
  return ui.row({ key = crash.id, padding = 10, gap = 12,
    fill = "surface_variant", radius = 8, align = "center" }, {
    ui.column({ gap = 3, flexGrow = 1 }, {
      ui.label({ text = crash.application, fontSize = 14, fontWeight = "bold", color = "on_surface", maxLines = 1 }),
      label(crash.date .. " · " .. crash.signal, 11, "on_surface/0.65", 1),
    }),
    ui.button({ text = "Détails", height = 30, variant = "outline", onClick = function() choose(crash) end }),
  })
end

local function content()
  if confirming then
    return {
      label("Envoyer ce rapport à Monarch ?", 21),
      label("Destination : " .. collection.endpoint, 13, "on_surface/0.8"),
      label("Vous confirmez l’envoi du rapport que vous venez de consulter, avec les versions et la backtrace affichées.", 13),
      label("Conservation annoncée : " .. tostring(collection.retentionDays) .. " jours. Les mainteneurs pourront consulter ce rapport.", 13, "on_surface/0.7"),
      label("Vous recevrez un lien unique à joindre à votre ticket GitHub. L’ouverture du lien exige un accès mainteneur.", 13, "on_surface/0.7"),
    }
  end
  if report then
    return {
      label("Rapport à partager", 21),
      label(receipt ~= "" and ("Rapport envoyé · " .. receipt)
        or "Vérifiez son contenu avant de le transmettre.", 12, receipt ~= "" and "primary" or "on_surface/0.65"),
      ui.label({ text = report, fontSize = 12, color = "on_surface", maxLines = 240 }),
    }
  end
  if selected then
    return {
      label(selected.application, 24),
      label(selected.date, 12, "on_surface/0.65"),
      ui.row({ padding = 12, radius = 8, fill = "surface_variant", gap = 12 }, {
        ui.column({ flexGrow = 1, gap = 4 }, {
          label("Signal", 11, "on_surface/0.65"), label(selected.signal, 15),
        }),
        ui.column({ flexGrow = 1, gap = 4 }, {
          label("Mémoire", 11, "on_surface/0.65"), label(coreLabels[selected.core] or coreLabels.unavailable, 13),
        }),
      }),
      label("Préparez un rapport avec les versions et la backtrace enregistrée par le système.", 13, "on_surface/0.8"),
      label("Le rapport exclut le dump mémoire, les variables d’environnement, la ligne de commande et les journaux généraux.", 12, "on_surface/0.65"),
      label("Si la backtrace est absente, le dump peut être analysé localement avec coredumpctl.", 12, "on_surface/0.65"),
    }
  end
  if loading then return { label("Chargement des crashes…", 14, "on_surface/0.7") } end
  if #crashes == 0 then
    return {
      label(status == "" and "Aucun crash enregistré" or "Historique indisponible", 21),
      label(status == "" and "Les plantages enregistrés par le système pour votre utilisateur apparaîtront ici."
        or "Vérifiez l’accès au journal système, puis actualisez.", 13, "on_surface/0.7"),
    }
  end
  local children = {}
  for i = (page - 1) * pageSize + 1, math.min(page * pageSize, #crashes) do
    table.insert(children, row(crashes[i]))
  end
  return children
end

function render()
  local children = {
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = "Crashes", fontSize = 15, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
      ui.button({ text = "Actualiser", variant = "ghost", height = 30, enabled = not loading and not selected, onClick = load }),
      ui.button({ glyph = "close", onClick = function() panel.close() end }),
    }),
    label(selected and "Diagnostic local" or "Les derniers plantages de vos applications", 12, "on_surface/0.65"),
    ui.scroll({ flexGrow = 1, gap = 8, align = "stretch" }, content()),
  }
  if status ~= "" then table.insert(children, label(status, 12, statusOk and "primary" or "error")) end
  if saved ~= "" and not confirming then
    table.insert(children, ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = "Export local disponible", fontSize = 11, color = "on_surface/0.55", flexGrow = 1 }),
      ui.button({ text = "Ouvrir le rapport", height = 30, variant = "ghost",
        onClick = function() noctalia.runAsync("xdg-open " .. quote(saved)) end }),
    }))
  end
  if selected then
    local buttons = {
      ui.button({ text = "Retour", height = 34, variant = "ghost", enabled = not exporting and not sending, onClick = onBackClicked }),
      ui.spacer({ flexGrow = 1 }),
    }
    if confirming then
      table.insert(buttons, ui.button({ text = sending and "Envoi…" or "Confirmer l’envoi", height = 34,
        variant = "primary", enabled = not sending, onClick = send }))
    elseif report then
      table.insert(buttons, ui.button({ text = exporting and "Export…" or "Exporter", height = 34,
        variant = "outline", enabled = not exporting, onClick = export }))
      if receipt ~= "" then
        table.insert(buttons, ui.button({ text = "Copier le lien du crash", height = 34,
          variant = "primary", enabled = not exporting, onClick = copyLink }))
      else
        table.insert(buttons, ui.button({ text = "Envoyer à Monarch", height = 34,
          variant = "primary", enabled = not exporting and collection ~= nil and collection.enabled == true,
          onClick = function() confirming = true; status = ""; render() end }))
      end
    else
      table.insert(buttons, ui.button({ text = loading and "Préparation…" or "Préparer le rapport", height = 34,
        variant = "primary", enabled = not loading, onClick = preview }))
    end
    local hint = "Aucun rapport n’est envoyé automatiquement."
    if report and receipt == "" and not confirming then
      if collection == nil then hint = "Vérification de la disponibilité de la collecte…"
      elseif not collection.enabled then hint = "L’envoi à Monarch est indisponible. Vous pouvez exporter le rapport." end
    end
    table.insert(children, label(hint, 11, "on_surface/0.55"))
    table.insert(children, ui.row({ gap = 8, align = "center" }, buttons))
  else
    local pages = math.max(1, math.ceil(#crashes / pageSize))
    table.insert(children, ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = tostring(#crashes) .. (more and "+" or "") .. " crashes · " .. tostring(page) .. " / " .. tostring(pages),
        fontSize = 11, color = "on_surface/0.55", flexGrow = 1 }),
      ui.button({ text = "Précédent", height = 30, enabled = page > 1,
        onClick = function() page -= 1; render() end }),
      ui.button({ text = "Suivant", height = 30, enabled = page < pages,
        onClick = function() page += 1; render() end }),
    }))
  end
  panel.render(ui.column({ flexGrow = 1, gap = 12 }, children))
end

function onOpen(context)
  local data = noctalia.json.decode(context or "")
  root = type(data) == "table" and type(data.root) == "string" and data.root
    or noctalia.getenv("MONARCH_PATH") or "/usr/share/monarch"
  requested = type(data) == "table" and type(data.id) == "string" and data.id or ""
  selected = nil
  report = nil
  saved = ""
  exporting = false
  sending = false
  confirming = false
  receipt = ""
  collection = nil
  statusOk = false
  load()
end

function onClose()
  generation += 1
  loading = false
  exporting = false
  sending = false
end

function onBackClicked()
  if exporting or sending then return end
  generation += 1
  loading = false
  status = ""
  if confirming then confirming = false
  elseif report then report = nil; receipt = ""; collection = nil
  else selected = nil end
  saved = ""
  render()
end

function onKey(chord, pressed)
  if pressed and chord == "left" then onBackClicked() end
end

function onIpc(event)
  if event == "refresh" then load()
  elseif event == "preview" then preview()
  elseif event == "export" then export()
  elseif event == "confirm" and not exporting and not sending and report and receipt == ""
    and collection and collection.enabled then
    confirming = true; render()
  elseif event == "send" then send()
  elseif event == "copy" then copyLink()
  elseif event == "back" then onBackClicked() end
end
