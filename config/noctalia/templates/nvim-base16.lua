-- Noctalia → base16-nvim bridge (Material Design 3 tokens → base16 slots).
-- Input template rendered by Noctalia into ~/.config/nvim/lua/matugen.lua.
-- Consumed by base16-nvim: `require('matugen').setup()` (see the monarch-nvim package).
-- Slot mapping follows https://docs.noctalia.dev/v4/theming/program-specific/neovim/
local M = {}

function M.setup()
  require("base16-colorscheme").setup({
    base00 = "{{colors.surface.default.hex}}",                -- default background
    base01 = "{{colors.surface_container.default.hex}}",      -- lighter background (status bars)
    base02 = "{{colors.surface_container_high.default.hex}}", -- selection background
    base03 = "{{colors.outline.default.hex}}",               -- comments, invisibles
    base04 = "{{colors.on_surface_variant.default.hex}}",     -- dark foreground (status bars)
    base05 = "{{colors.on_surface.default.hex}}",             -- default foreground
    base06 = "{{colors.on_surface.default.hex}}",             -- light foreground
    base07 = "{{colors.on_background.default.hex}}",          -- light background
    base08 = "{{colors.error.default.hex}}",                  -- variables, diff deleted
    base09 = "{{colors.tertiary.default.hex}}",               -- integers, constants
    base0A = "{{colors.secondary.default.hex}}",              -- classes, search bg
    base0B = "{{colors.primary.default.hex}}",                -- strings, diff added
    base0C = "{{colors.tertiary_fixed_dim.default.hex}}",     -- escapes, regex
    base0D = "{{colors.primary_fixed_dim.default.hex}}",      -- functions, methods
    base0E = "{{colors.secondary_fixed_dim.default.hex}}",    -- keywords
    base0F = "{{colors.error_container.default.hex}}",        -- deprecated
  })
end

return M
