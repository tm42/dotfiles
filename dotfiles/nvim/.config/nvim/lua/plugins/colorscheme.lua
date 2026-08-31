-- ============================================================================
-- Colorscheme: Catppuccin (mocha)
-- ============================================================================
-- priority 1000 loads this before every other start plugin, so nothing renders
-- one frame in the default scheme first.
--
-- transparent_background stays false on purpose: .tmux.conf paints the active
-- pane #002b36, and transparency would show that through instead of catppuccin's
-- own ground — which is what the Claude statusline's palette is matched against.
--
-- The integrations list is load-bearing, not decoration. A plugin missing from it
-- keeps its own default highlights and stops matching everything else, so adding
-- a plugin with its own UI means adding it here too.
-- ============================================================================

return {
  "catppuccin/nvim",
  name = "catppuccin",
  priority = 1000, -- Load before other plugins
  config = function()
    require("catppuccin").setup({
      flavour = "mocha", -- Options: latte, frappe, macchiato, mocha
      transparent_background = false,
      integrations = {
        cmp = true,
        gitsigns = true,
        nvimtree = true,
        neotree = true,
        treesitter = true,
        mason = true,
        which_key = true,
        telescope = { enabled = true },
        native_lsp = {
          enabled = true,
          underlines = {
            errors = { "undercurl" },
            hints = { "undercurl" },
            warnings = { "undercurl" },
            information = { "undercurl" },
          },
        },
      },
    })
    -- Activate the colorscheme
    vim.cmd.colorscheme("catppuccin")
  end,
}
