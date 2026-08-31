-- ============================================================================
-- Gitsigns: hunks in the file you are looking at
-- ============================================================================
-- The gutter marks, plus <leader>h* to stage / reset / preview / blame a hunk
-- and ]h / [h to walk them. Signs and options are gitsigns' defaults.
--
-- Scope boundary worth keeping straight: this is the working tree against the
-- index, one file at a time. For two points in history — a branch, HEAD~3, a
-- merge conflict — that is diffview.lua on <leader>g*.
-- ============================================================================

return {
  "lewis6991/gitsigns.nvim",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    require("gitsigns").setup({
      signs = {
        add          = { text = "│" },
        change       = { text = "│" },
        delete       = { text = "_" },
        topdelete    = { text = "‾" },
        changedelete = { text = "~" },
        untracked    = { text = "┆" },
      },

      -- Keymaps
      on_attach = function(bufnr)
        local gs = package.loaded.gitsigns
        local opts = { buffer = bufnr }

        local function map(mode, l, r, desc)
          opts.desc = desc
          vim.keymap.set(mode, l, r, opts)
        end

        -- Navigation between hunks
        map("n", "]h", gs.next_hunk, "Next git hunk")
        map("n", "[h", gs.prev_hunk, "Previous git hunk")

        -- Actions
        map("n", "<leader>hs", gs.stage_hunk, "Stage hunk")
        map("n", "<leader>hr", gs.reset_hunk, "Reset hunk")
        map("v", "<leader>hs", function() gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, "Stage selected")
        map("v", "<leader>hr", function() gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, "Reset selected")
        map("n", "<leader>hS", gs.stage_buffer, "Stage buffer")
        map("n", "<leader>hu", gs.undo_stage_hunk, "Undo stage hunk")
        map("n", "<leader>hR", gs.reset_buffer, "Reset buffer")
        map("n", "<leader>hp", gs.preview_hunk, "Preview hunk")
        map("n", "<leader>hb", function() gs.blame_line({ full = true }) end, "Blame line")
        map("n", "<leader>hd", gs.diffthis, "Diff this")
        map("n", "<leader>hD", function() gs.diffthis("~") end, "Diff this (~)")

        -- Toggle blame line
        map("n", "<leader>tb", gs.toggle_current_line_blame, "Toggle line blame")
      end,
    })
  end,
}
