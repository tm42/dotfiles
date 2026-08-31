-- ============================================================================
-- Neovim Configuration Entry Point
-- ============================================================================
-- This file loads all configuration modules in the correct order.
-- Structure:
--   lua/options.lua  - Core Neovim settings (line numbers, tabs, etc.)
--   lua/keymaps.lua  - Custom keybindings
--   lua/plugins/     - Plugin configurations (managed by lazy.nvim)
-- ============================================================================

-- Set leader key BEFORE loading plugins (important!)
-- The leader key is your personal prefix for custom commands
-- Press <Space> then another key to trigger commands
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Load core configuration
require("options")   -- Editor settings
require("keymaps")   -- Key mappings

-- Bootstrap lazy.nvim (plugin manager)
-- This will auto-install lazy.nvim if it's not present
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  local out = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
  -- Without this check a failed clone (no network, proxy, corporate TLS) throws
  -- "module 'lazy' not found" with a traceback on every launch. options and
  -- keymaps are already loaded above, so returning here leaves a plain but
  -- working nvim and one readable message.
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "lazy.nvim clone failed — no plugins will load.\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nFix the clone and restart nvim.", "Normal" },
    }, true, {})
    return
  end
end
vim.opt.rtp:prepend(lazypath)

-- Load plugins from lua/plugins/ directory
-- Each file in that directory returns a plugin spec
require("lazy").setup("plugins", {
  -- Check for plugin updates on startup (but don't auto-install)
  checker = { enabled = true, notify = false },
  -- Don't show notifications for config changes
  change_detection = { notify = false },
})
