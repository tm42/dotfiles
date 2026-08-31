-- ============================================================================
-- Mini.map: Code Minimap
-- ============================================================================
-- Toggle with <leader>mm; the autocmd at the bottom opens it for real files and
-- skips neo-tree, Telescope, lazy, mason, help and quickfix.
--
-- The four nvim_set_hl calls below hardcode catppuccin mocha's own hex values
-- because mini.map's defaults are too dim to read at width 12. They are pinned,
-- not derived — switch flavour in colorscheme.lua and the minimap alone stops
-- matching.
-- ============================================================================

return {
  "echasnovski/mini.map",
  version = false,
  event = { "BufReadPost", "BufNewFile" },
  keys = {
    { "<leader>mm", function() require("mini.map").toggle() end, desc = "Toggle minimap" },
  },
  config = function()
    local map = require("mini.map")

    -- Brighter minimap colors (override theme defaults)
    vim.api.nvim_set_hl(0, "MiniMapNormal",      { fg = "#89b4fa", bg = "#1e1e2e" }) -- Blue code dots
    vim.api.nvim_set_hl(0, "MiniMapSymbolCount",  { fg = "#cdd6f4" })                -- Light text
    vim.api.nvim_set_hl(0, "MiniMapSymbolLine",   { fg = "#f38ba8" })                -- Red scroll indicator
    vim.api.nvim_set_hl(0, "MiniMapSymbolView",   { fg = "#a6e3a1" })                -- Green viewport bar

    map.setup({
      -- Encode the buffer content into the minimap
      integrations = {
        map.gen_integration.builtin_search(),
        map.gen_integration.diagnostic(),
        map.gen_integration.gitsigns(),
      },

      -- Symbols used to render the minimap
      symbols = {
        encode = map.gen_encode_symbols.dot("4x2"),
        scroll_line = "▶",
        scroll_view = "┃",
      },

      window = {
        side = "right",
        width = 12,
        winblend = 10,    -- Low transparency = more visible
        show_integration_count = false,
      },
    })

    -- Auto-open minimap when opening a file
    vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
      callback = function()
        local ft = vim.bo.filetype
        -- Don't show minimap for special buffers
        local exclude = { "neo-tree", "Telescope", "lazy", "mason", "help", "qf", "" }
        for _, v in ipairs(exclude) do
          if ft == v then return end
        end
        if vim.bo.buftype ~= "" then return end
        map.open()
      end,
    })
  end,
}
