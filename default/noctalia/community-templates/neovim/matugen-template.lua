-- SPDX-License-Identifier: MIT
local theme = {}

function theme.setup()
  vim.o.background = "{{ mode }}"
  vim.g.colors_name = "noctalia"
  local colors = {
    background = "{{ colors.terminal_background.default.hex }}",
    foreground = "{{ colors.terminal_foreground.default.hex }}",
    muted = "{{ colors.on_surface_variant.default.hex }}",
    panel = "{{ colors.surface_container.default.hex }}",
    accent = "{{ colors.primary.default.hex }}",
    red = "{{ colors.terminal_normal_red.default.hex }}",
    green = "{{ colors.terminal_normal_green.default.hex }}",
    yellow = "{{ colors.terminal_normal_yellow.default.hex }}",
    blue = "{{ colors.terminal_normal_blue.default.hex }}",
    magenta = "{{ colors.terminal_normal_magenta.default.hex }}",
    cyan = "{{ colors.terminal_normal_cyan.default.hex }}",
  }
  local groups = {
    Normal = { fg = colors.foreground, bg = colors.background },
    NormalFloat = { fg = colors.foreground, bg = colors.panel },
    FloatBorder = { fg = colors.accent, bg = colors.panel },
    Comment = { fg = colors.muted, italic = true },
    Constant = { fg = colors.magenta },
    String = { fg = colors.green },
    Number = { fg = colors.yellow },
    Boolean = { fg = colors.yellow },
    Identifier = { fg = colors.foreground },
    Function = { fg = colors.blue },
    Statement = { fg = colors.magenta },
    PreProc = { fg = colors.cyan },
    Type = { fg = colors.yellow },
    Special = { fg = colors.cyan },
    Error = { fg = colors.red },
    DiagnosticError = { fg = colors.red },
    DiagnosticWarn = { fg = colors.yellow },
    DiagnosticInfo = { fg = colors.blue },
    DiagnosticHint = { fg = colors.cyan },
    LineNr = { fg = colors.muted },
    CursorLineNr = { fg = colors.accent, bold = true },
    CursorLine = { bg = colors.panel },
    SignColumn = { bg = colors.background },
    StatusLine = { fg = colors.foreground, bg = colors.panel },
    Visual = { bg = "{{ colors.terminal_selection_bg.default.hex }}" },
    Search = { fg = "{{ colors.on_primary.default.hex }}", bg = colors.accent },
    Pmenu = { fg = colors.foreground, bg = colors.panel },
    PmenuSel = { fg = "{{ colors.on_primary.default.hex }}", bg = colors.accent },
    ["@variable"] = { fg = colors.foreground },
    ["@keyword"] = { link = "Statement" },
    ["@function"] = { link = "Function" },
    ["@string"] = { link = "String" },
    ["@type"] = { link = "Type" },
  }
  for name, attributes in pairs(groups) do
    vim.api.nvim_set_hl(0, name, attributes)
  end
end

return theme
