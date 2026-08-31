-- ============================================================================
-- Neo-tree: File Explorer
-- ============================================================================
-- <leader>e toggles, <leader>o focuses. Mostly neo-tree's defaults; the
-- filtering is inverted from the usual and that is on purpose:
--   hide_dotfiles  = false   dotfiles ARE the work in this repo
--   hide_gitignored = true   build output is not
--
-- <space> is mapped to "none" inside the tree so the leader key still works
-- while the tree has focus.
-- ============================================================================

return {
  "nvim-neo-tree/neo-tree.nvim",
  branch = "v3.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-web-devicons", -- File icons
    "MunifTanjim/nui.nvim",
  },
  cmd = "Neotree",
  keys = {
    { "<leader>e", "<cmd>Neotree toggle<CR>", desc = "Toggle file explorer" },
    { "<leader>o", "<cmd>Neotree focus<CR>", desc = "Focus file explorer" },
  },
  config = function()
    require("neo-tree").setup({
      close_if_last_window = true,
      popup_border_style = "rounded",
      enable_git_status = true,
      enable_diagnostics = true,

      filesystem = {
        filtered_items = {
          visible = false, -- Hidden files are hidden by default
          hide_dotfiles = false, -- But show dotfiles (like .gitignore)
          hide_gitignored = true, -- Hide git-ignored files
          hide_by_name = {
            ".git",
            "node_modules",
            "__pycache__",
            ".venv",
          },
        },
        follow_current_file = {
          enabled = true, -- Auto-reveal current file
        },
        use_libuv_file_watcher = true, -- Auto-refresh on file changes
      },

      window = {
        position = "left",
        width = 35,
        mappings = {
          ["<space>"] = "none", -- Don't conflict with leader key
          ["<cr>"] = "open",
          ["o"] = "open",
          ["s"] = "open_vsplit",
          ["S"] = "open_split",
          ["a"] = "add",        -- Add file
          ["A"] = "add_directory",
          ["d"] = "delete",
          ["r"] = "rename",
          ["c"] = "copy",
          ["m"] = "move",
          ["q"] = "close_window",
          ["R"] = "refresh",
          ["?"] = "show_help",
          ["H"] = "toggle_hidden",
        },
      },

      default_component_configs = {
        git_status = {
          symbols = {
            added     = "✚",
            modified  = "",
            deleted   = "✖",
            renamed   = "󰁕",
            untracked = "",
            ignored   = "",
            unstaged  = "󰄱",
            staged    = "",
            conflict  = "",
          },
        },
      },
    })
  end,
}
