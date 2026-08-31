-- ============================================================================
-- Telescope: Fuzzy Finder
-- ============================================================================
-- <leader>f* — files, live grep, buffers, recent, word under cursor, plus fk /
-- fc / fh for keymaps, commands and help. <leader>fk is the nvim answer to
-- tmux's C-a F: every binding, searchable.
--
-- live_grep and grep_string exec `rg` directly, so ripgrep must be a real binary
-- on PATH — a shell function or alias named rg is invisible to them.
--
-- telescope-fzf-native is compiled (`build = "make"`), so it needs a C compiler
-- that INSTALL.md does not install. Its load is wrapped in pcall for that
-- reason: without it, a failed build takes every key above down with it.
-- ============================================================================

return {
  "nvim-telescope/telescope.nvim",
  branch = "0.1.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    -- Native FZF sorter for better performance
    {
      "nvim-telescope/telescope-fzf-native.nvim",
      build = "make",
    },
  },
  cmd = "Telescope",
  keys = {
    -- File navigation
    { "<leader>ff", "<cmd>Telescope find_files<CR>", desc = "Find files" },
    { "<leader>fg", "<cmd>Telescope live_grep<CR>", desc = "Find text (grep)" },
    { "<leader>fb", "<cmd>Telescope buffers<CR>", desc = "Find buffers" },
    { "<leader>fr", "<cmd>Telescope oldfiles<CR>", desc = "Recent files" },

    -- Search
    { "<leader>fw", "<cmd>Telescope grep_string<CR>", desc = "Find word under cursor" },
    { "<leader>/", "<cmd>Telescope current_buffer_fuzzy_find<CR>", desc = "Search in buffer" },

    -- Git
    { "<leader>gc", "<cmd>Telescope git_commits<CR>", desc = "Git commits" },
    { "<leader>gs", "<cmd>Telescope git_status<CR>", desc = "Git status" },

    -- Help & Neovim
    { "<leader>fh", "<cmd>Telescope help_tags<CR>", desc = "Help tags" },
    { "<leader>fk", "<cmd>Telescope keymaps<CR>", desc = "Keymaps" },
    { "<leader>fc", "<cmd>Telescope commands<CR>", desc = "Commands" },

    -- LSP
    { "<leader>fs", "<cmd>Telescope lsp_document_symbols<CR>", desc = "Document symbols" },
    { "<leader>fS", "<cmd>Telescope lsp_workspace_symbols<CR>", desc = "Workspace symbols" },
  },
  config = function()
    local telescope = require("telescope")
    local actions = require("telescope.actions")

    telescope.setup({
      defaults = {
        -- Search pattern shown in prompt
        prompt_prefix = " 🔍 ",
        selection_caret = " → ",

        -- How to handle results
        path_display = { "truncate" },
        sorting_strategy = "ascending",
        layout_config = {
          horizontal = {
            prompt_position = "top",
            preview_width = 0.55,
          },
          width = 0.87,
          height = 0.80,
        },

        -- Keymaps within Telescope
        mappings = {
          i = {
            ["<C-j>"] = actions.move_selection_next,
            ["<C-k>"] = actions.move_selection_previous,
            ["<C-q>"] = actions.send_selected_to_qflist + actions.open_qflist,
            ["<Esc>"] = actions.close,
          },
        },

        -- Ignore patterns
        file_ignore_patterns = {
          "node_modules",
          ".git/",
          "*.pyc",
          "__pycache__",
          ".venv",
          "venv",
        },
      },
      pickers = {
        find_files = {
          hidden = true, -- Show hidden files
        },
      },
    })

    -- Load FZF extension for better sorting.
    -- pcall, because telescope's loader calls error() when an extension fails to
    -- require: the `build = "make"` above needs a C compiler that INSTALL.md does
    -- not install, and a bare call would abort this whole config function and
    -- take all fourteen Telescope keys with it. Unwrapped, we lose the native
    -- sorter and keep everything else.
    pcall(telescope.load_extension, "fzf")
  end,
}
