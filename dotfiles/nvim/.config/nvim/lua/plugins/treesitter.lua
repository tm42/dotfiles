-- ============================================================================
-- Treesitter: Parser Installation & Highlighting
-- ============================================================================
-- Ten parsers, installed on first launch if missing. Highlighting is Neovim's
-- own (vim.treesitter.start on FileType), not nvim-treesitter's module — the
-- pinned main branch no longer ships one.
--
-- That branch also shells out to the tree-sitter CLI and a C compiler, which is
-- what the guard in the config below is about.
-- ============================================================================

return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  event = { "BufReadPost", "BufNewFile" },
  config = function()
    -- List of parsers to install
    local parsers = {
      "python", "lua", "vim", "vimdoc", "bash",
      "json", "yaml", "toml", "markdown", "markdown_inline",
    }

    -- Install missing parsers on startup, in ONE :TSInstall rather than ten.
    vim.schedule(function()
      local missing = {}
      for _, parser in ipairs(parsers) do
        if not pcall(vim.treesitter.language.inspect, parser) then
          table.insert(missing, parser)
        end
      end
      if #missing == 0 then
        return
      end
      -- The pinned main branch shells out to the tree-sitter CLI and a C
      -- compiler, neither of which INSTALL.md installs. Without them every
      -- install fails, and the next launch retries and fails identically —
      -- forever, with no message. Say it once instead.
      if vim.fn.executable("tree-sitter") == 0 or vim.fn.executable("cc") == 0 then
        vim.notify(
          ("treesitter: %d parsers missing, and tree-sitter or cc is not on PATH. "
            .. "Install both, then :TSInstall %s"):format(#missing, table.concat(missing, " ")),
          vim.log.levels.WARN
        )
        return
      end
      vim.cmd("TSInstall " .. table.concat(missing, " "))
    end)

    -- Auto-enable treesitter highlighting for supported filetypes
    vim.api.nvim_create_autocmd("FileType", {
      callback = function()
        pcall(vim.treesitter.start)
      end,
    })
  end,
}
