-- ============================================================================
-- vim-tmux-navigator: nvim splits and tmux panes as one grid
-- ============================================================================
-- M-hjkl walks out of an nvim split straight into the neighbouring tmux pane
-- and back. tmux only forwards the key when the pane is actually running nvim
-- (the is_vim check in ~/.tmux.conf) — so the two halves must agree on the
-- mapping. Change it here, change it there.
-- ============================================================================

return {
  "christoomey/vim-tmux-navigator",
  init = function()
    -- the plugin's own C-hjkl defaults would shadow nvim's window commands
    vim.g.tmux_navigator_no_mappings = 1
    -- a zoomed tmux pane stays zoomed; walking out of it silently unzooms otherwise
    vim.g.tmux_navigator_disable_when_zoomed = 1
  end,
  cmd = { "TmuxNavigateLeft", "TmuxNavigateDown", "TmuxNavigateUp", "TmuxNavigateRight" },
  keys = {
    { "<M-h>", "<cmd>TmuxNavigateLeft<cr>",  desc = "Go to left split/pane" },
    { "<M-j>", "<cmd>TmuxNavigateDown<cr>",  desc = "Go to lower split/pane" },
    { "<M-k>", "<cmd>TmuxNavigateUp<cr>",    desc = "Go to upper split/pane" },
    { "<M-l>", "<cmd>TmuxNavigateRight<cr>", desc = "Go to right split/pane" },
  },
}
