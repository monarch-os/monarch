--!strict
-- The menu's pure logic: indexing the tree, resolving routes, deciding what is
-- visible and searching. Nothing here touches the UI or the shell, which is what
-- makes it the piece worth keeping in step with bin/monarch-menu's data layer —
-- both describe the same tree and must agree about it.

local M = {}

export type Entry = {
  icon: string?,
  label: string?,
  title: string?,
  action: string?,
  target: string?,
  provider: string?,
  aliases: { string }?,
  description: string?,
  keywords: { string }?,
  when: string?,
  checked: string?,
  disabled: string?,
  disabledLabel: string?,
  searchText: string?,
  hiddenAtRoot: boolean?,
  rootGroup: string?,
}

export type Menu = {
  entries: { [string]: Entry },
  -- Declaration order, which the shipped file relies on: rows appear in the
  -- order they are written, and an overridden entry keeps its position.
  order: { string },
  -- Parent -> children, and child -> parent, both built in fromArray's single
  -- pass so no level ever has to scan the whole tree.
  children: { [string]: { string } },
  parents: { [string]: string },
  crumbs: { [string]: string },
  -- What a row is matched against, built once and kept: the string never changes
  -- while the tree is loaded, and rebuilding it per entry per keystroke was most
  -- of what a search cost.
  haystacks: { [string]: string },
}

-- The panel never parses the JSONC itself. `monarch-menu --state` already loads
-- the shipped file, overlays the user's and emits one ordered array alongside
-- every evaluated guard, so this is a plain decode of what bash produced.
--
-- That split is not only taste: a plugin callback has a CPU budget, and a
-- line-by-line strip of the 40 kB JSONC in Luau exceeds it. Decoding what bash
-- already normalised is one native call — measured in the VM at 38 kB, 266
-- entries, 3 ms including the indexing below. Keeping one loader in bash also
-- means the CLI and the panel cannot disagree about what the menu contains.
function M.fromArray(rows: any): Menu?
  if type(rows) ~= "table" then
    return nil
  end

  local entries = {}
  local order = {}
  local children = {}
  local parents = {}

  -- One pass builds the parent index too. Deriving children by scanning every
  -- entry per level looks harmless at this size but is quadratic once isVisible
  -- recurses: ~70 000 pattern matches per open, which is what the host's
  -- per-callback CPU budget was killing. Indexed, the whole load is ~3 ms.
  for _, row in rows do
    local id = row.id
    if type(id) == "string" and id ~= "" then
      entries[id] = row
      table.insert(order, id)

      local parent = id:match("^(.*)%.[^.]+$") or "root"
      parents[id] = parent
      local bucket = children[parent]
      if bucket then
        table.insert(bucket, id)
      else
        children[parent] = { id }
      end
    end
  end

  if #order == 0 then
    return nil
  end

  return {
    entries = entries,
    order = order,
    children = children,
    parents = parents,
    crumbs = {},
    haystacks = {},
  }
end

function M.parentOf(menu: Menu, id: string): string
  return menu.parents[id] or "root"
end

function M.lastSegment(id: string): string
  return id:match("([^.]+)$") or id
end

function M.childrenOf(menu: Menu, parent: string): { string }
  return menu.children[parent] or {}
end

function M.labelOf(menu: Menu, id: string): string
  local entry = menu.entries[id]
  if entry and entry.label and entry.label ~= "" then
    return entry.label
  end
  return M.lastSegment(id)
end

function M.titleOf(menu: Menu, id: string): string
  if id == "root" then
    return "Go"
  end
  local entry = menu.entries[id]
  if entry then
    if entry.title and entry.title ~= "" then
      return entry.title
    end
    if entry.label and entry.label ~= "" then
      return entry.label
    end
  end
  return M.lastSegment(id)
end

-- Exact id, then a declared alias, then the last segment of an id. An unknown
-- route is returned unchanged so a typo fails visibly rather than silently
-- opening the root menu. Kept byte-for-byte equivalent to resolve_route in
-- bin/monarch-menu.
function M.resolveRoute(menu: Menu, route: string?): string
  local wanted = (route or ""):lower():gsub("_", "-")
  if wanted == "" or wanted == "go" or wanted == "menu" or wanted == "root" then
    return "root"
  end

  for _, id in menu.order do
    if id:lower() == wanted then
      return id
    end
  end

  for _, id in menu.order do
    local entry = menu.entries[id]
    if entry and entry.aliases then
      for _, alias in entry.aliases do
        if alias:lower() == wanted then
          return id
        end
      end
    end
  end

  for _, id in menu.order do
    if M.lastSegment(id):lower() == wanted then
      return id
    end
  end

  return wanted
end

-- A submenu whose visible descendants are all hidden disappears with them,
-- matching quattro. Provider-backed submenus always stay: their rows only
-- exist at runtime.
function M.isVisible(menu: Menu, id: string, guards: { [string]: boolean }): boolean
  local entry = menu.entries[id]
  if not entry then
    return false
  end

  if entry.when and entry.when ~= "" and guards[id .. ":w"] == false then
    return false
  end

  if entry.hiddenAtRoot and M.parentOf(menu, id) == "root" then
    return false
  end

  if entry.action or entry.target or entry.provider then
    return true
  end

  for _, child in M.childrenOf(menu, id) do
    if M.isVisible(menu, child, guards) then
      return true
    end
  end

  return false
end

function M.visibleChildren(menu: Menu, parent: string, guards: { [string]: boolean }): { string }
  local out = {}
  for _, id in M.childrenOf(menu, parent) do
    if M.isVisible(menu, id, guards) then
      table.insert(out, id)
    end
  end
  return out
end

-- Search is bounded by the open level, as quattro's is: from Trigger it only
-- looks inside Trigger. Every hit is then something reachable from where the
-- user already is, and the path each row prints stays short enough to read.
-- A row is matched on its own name — its label and its last id segment — and
-- never on its ancestry. Under a level the ancestry is the same for every row,
-- so folding it in only adds false hits: inside Install > Development, "p"
-- answered for Go, Zig and Java, on the "p" of "development".
--
-- Results are capped because this runs on every keystroke, inside a callback the
-- host kills when it takes too long: a loose query matches most of the tree, and
-- rendering 200 rows nobody scrolls to is what busted the budget.
local SEARCH_LIMIT = 40

-- The shipped tree is four levels deep; the bound only stops a malformed parent
-- chain from spinning.
local function isDescendant(menu: Menu, id: string, ancestor: string): boolean
  if ancestor == "root" then
    return true
  end
  local cursor = M.parentOf(menu, id)
  for _ = 1, 32 do
    if cursor == ancestor then
      return true
    end
    if cursor == "root" then
      return false
    end
    cursor = M.parentOf(menu, cursor)
  end
  return false
end

export type Hit = { id: string, group: string }

local function searchGroup(menu: Menu, id: string, ancestor: string): string
  local group = id
  local parent = M.parentOf(menu, group)
  for _ = 1, 32 do
    if parent == ancestor or parent == "root" then
      local entry = menu.entries[group]
      if ancestor == "root" and entry and entry.rootGroup then
        return entry.rootGroup
      end
      return group
    end
    group = parent
    parent = M.parentOf(menu, group)
  end
  return id
end

function M.search(menu: Menu, query: string, guards: { [string]: boolean }, active: string?): { Hit }
  local from = active or "root"
  local matches = {}
  local groupRanks = {}
  for index, id in M.childrenOf(menu, from) do
    groupRanks[id] = index
  end

  for _, id in menu.order do
    local entry = menu.entries[id]
    if
      entry
      and (entry.action or entry.provider)
      and isDescendant(menu, id, from)
      and M.isVisible(menu, id, guards)
    then
      -- An empty query lists everything in declaration order: that is what the
      -- launcher shows before a single character is typed.
      if query == "" then
        table.insert(matches, { id = id, score = 0, group = searchGroup(menu, id, from) })
      else
        local haystack = menu.haystacks[id]
        if not haystack then
          haystack = entry.searchText or (M.labelOf(menu, id) .. " " .. M.lastSegment(id))
          menu.haystacks[id] = haystack
        end
        local score = noctalia.fuzzyScore(query, haystack)
        if score then
          table.insert(matches, {
            id = id,
            score = score,
            group = searchGroup(menu, id, from),
          })
        end
      end
    end
  end

  if query == "" then
    return matches
  end

  table.sort(matches, function(a, b)
    local aRank = groupRanks[a.group] or 9999
    local bRank = groupRanks[b.group] or 9999
    if aRank ~= bRank then
      return aRank < bRank
    end
    if a.score == b.score then
      return a.id < b.id
    end
    return a.score > b.score
  end)

  for index = #matches, SEARCH_LIMIT + 1, -1 do
    matches[index] = nil
  end
  return matches
end

-- The path shown in the header, e.g. "Trigger › Capture". Memoised on the menu:
-- the search view asks for one per row on every keystroke.
function M.breadcrumb(menu: Menu, id: string): string
  if id == "root" then
    return M.titleOf(menu, "root")
  end

  if menu.crumbs[id] then
    return menu.crumbs[id]
  end

  local segments = {}
  local cursor = id
  while cursor ~= "root" do
    table.insert(segments, 1, M.titleOf(menu, cursor))
    cursor = M.parentOf(menu, cursor)
  end
  local crumb = table.concat(segments, " › ")
  menu.crumbs[id] = crumb
  return crumb
end

return M
