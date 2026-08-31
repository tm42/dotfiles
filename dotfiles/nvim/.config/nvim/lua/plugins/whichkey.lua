-- ============================================================================
-- Which-Key: what does <leader> do again
-- ============================================================================
-- Hold the leader for timeoutlen and it lists what can follow. 300ms is set in
-- init rather than config, because timeoutlen has to be in place before the
-- first keypress, and config runs at VeryLazy.
--
-- wk.add() below names the GROUPS. Without it the popup shows eight bare letters;
-- with it, "f  Find (Telescope)". The labels are hand-maintained and nothing
-- checks them — a group renamed here and not in keymaps.lua just lies quietly.
-- ============================================================================

return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  init = function()
    vim.o.timeout = true
    vim.o.timeoutlen = 300
  end,
  config = function()
    local wk = require("which-key")

    wk.setup({
      plugins = {
        marks = true,
        registers = true,
        spelling = { enabled = false },
      },
      win = {
        border = "rounded",
        padding = { 2, 2, 2, 2 },
      },
      layout = {
        height = { min = 4, max = 25 },
        width = { min = 20, max = 50 },
        spacing = 3,
      },
    })

    -- Register key group labels
    wk.add({
      { "<leader>f", group = "Find (Telescope)" },
      { "<leader>g", group = "Git" },
      { "<leader>h", group = "Git Hunks" },
      { "<leader>n", group = "New" },
      { "<leader>s", group = "Split" },
      { "<leader>b", group = "Buffer" },
      { "<leader>c", group = "Code" },
      { "<leader>t", group = "Toggle" },
    })
  end,
}
