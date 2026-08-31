-- ============================================================================
-- Diffview: Compare Two Refs Side by Side
-- ============================================================================
-- Gitsigns shows what changed in the file you are looking at. This shows what
-- changed between two points in history:
-- - A file panel listing ONLY the changed files
-- - Select one and get old (left) vs new (right), with word-level highlights
-- - A three-way view for merge conflicts
--
-- Lazy-loaded on its commands, so it costs nothing at startup.
-- ============================================================================

return {
  "sindrets/diffview.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles" },
  keys = {
    { "<leader>gv", "<cmd>DiffviewOpen<CR>", desc = "Diff working tree" },
    { "<leader>gV", "<cmd>DiffviewClose<CR>", desc = "Close diffview" },
    { "<leader>gh", "<cmd>DiffviewFileHistory %<CR>", desc = "History: this file" },
    { "<leader>gH", "<cmd>DiffviewFileHistory<CR>", desc = "History: whole repo" },
    {
      -- Prompt rather than hardcode: the interesting comparison is almost never
      -- the working tree. Takes anything git does — main, HEAD~3, a..b, a...b.
      "<leader>gr",
      function()
        vim.ui.input({ prompt = "Diff against ref: " }, function(ref)
          if ref and ref ~= "" then
            vim.cmd("DiffviewOpen " .. ref)
          end
        end)
      end,
      desc = "Diff against a ref",
    },
  },
  opts = {
    enhanced_diff_hl = true,   -- word-level highlights inside a changed line
    view = {
      merge_tool = { layout = "diff3_mixed" },  -- ours | base | theirs
    },
  },
}
