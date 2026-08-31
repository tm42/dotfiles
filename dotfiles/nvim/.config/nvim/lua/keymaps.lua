-- ============================================================================
-- Keymaps
-- ============================================================================
-- Custom keybindings for Neovim.
-- Leader key is <Space> (set in init.lua)
--
-- Notation:
--   <leader>  = Space
--   <C-x>     = Ctrl + x
--   <S-x>     = Shift + x
--   <A-x>     = Alt + x
-- ============================================================================

local keymap = vim.keymap.set

-- Better escape - press jk quickly to exit insert mode
keymap("i", "jk", "<Esc>", { desc = "Exit insert mode" })

-- Clear search highlighting with Escape
keymap("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- Save file with Ctrl+s (common muscle memory)
keymap({ "n", "i", "v" }, "<C-s>", "<cmd>w<CR><Esc>", { desc = "Save file" })

-- Quit with leader+q
keymap("n", "<leader>q", "<cmd>q<CR>", { desc = "Quit" })
keymap("n", "<leader>Q", "<cmd>qa!<CR>", { desc = "Quit all (force)" })

-- ============================================================================
-- Window Navigation (splits)
-- ============================================================================
-- Move between windows with Ctrl + hjkl
keymap("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
keymap("n", "<C-j>", "<C-w>j", { desc = "Move to lower window" })
keymap("n", "<C-k>", "<C-w>k", { desc = "Move to upper window" })
keymap("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })

-- Resize windows with Ctrl+Arrow keys
keymap("n", "<C-Up>", "<cmd>resize +2<CR>", { desc = "Increase window height" })
keymap("n", "<C-Down>", "<cmd>resize -2<CR>", { desc = "Decrease window height" })
keymap("n", "<C-Left>", "<cmd>vertical resize -2<CR>", { desc = "Decrease window width" })
keymap("n", "<C-Right>", "<cmd>vertical resize +2<CR>", { desc = "Increase window width" })

-- Split windows
keymap("n", "<leader>sv", "<cmd>vsplit<CR>", { desc = "Split vertical" })
keymap("n", "<leader>sh", "<cmd>split<CR>", { desc = "Split horizontal" })
keymap("n", "<leader>sx", "<cmd>close<CR>", { desc = "Close split" })

-- ============================================================================
-- New Files & Buffers
-- ============================================================================
-- ns/nS prefill the cmdline with the current file's directory and stop there —
-- no trailing <CR>. Type a name and Enter to create it, or press Tab to pick an
-- existing one from the popup (wildoptions=pum is the default, so it is a menu).
--
-- %:p:h and not %:h: with :p the path is made absolute first, so a buffer with
-- no file behind it (neo-tree, an unnamed :enew) falls back to the cwd instead
-- of expanding to "" or a bare ".". fnameescape covers directories with spaces.
keymap("n", "<leader>ns", ":vsplit <C-r>=fnameescape(expand('%:p:h'))<CR>/",
  { desc = "New file in vsplit (file's dir)" })
keymap("n", "<leader>nS", ":split <C-r>=fnameescape(expand('%:p:h'))<CR>/",
  { desc = "New file in hsplit (file's dir)" })

-- Scratch buffers: no name, no path step. Naming happens at :w time.
keymap("n", "<leader>nb", "<cmd>vnew<CR>", { desc = "New buffer in vsplit" })
keymap("n", "<leader>nB", "<cmd>new<CR>", { desc = "New buffer in hsplit" })

-- ============================================================================
-- Buffer Navigation
-- ============================================================================
keymap("n", "<S-l>", "<cmd>bnext<CR>", { desc = "Next buffer" })
keymap("n", "<S-h>", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
keymap("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "Delete buffer" })

-- ============================================================================
-- Text Manipulation
-- ============================================================================
-- Move lines up/down in visual mode
keymap("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
keymap("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- Stay in visual mode when indenting
keymap("v", "<", "<gv", { desc = "Indent left" })
keymap("v", ">", ">gv", { desc = "Indent right" })

-- No <C-d>zz / <C-u>zz here: neoscroll (misc.lua) maps both keys itself at
-- VeryLazy, which is after this file loads, so its smooth scroll wins and the zz
-- never runs. It recentres on its own.

-- Keep cursor centered when searching
keymap("n", "n", "nzzzv", { desc = "Next search result (centered)" })
keymap("n", "N", "Nzzzv", { desc = "Previous search result (centered)" })

-- Don't yank on paste in visual mode (keep original clipboard)
keymap("v", "p", '"_dP', { desc = "Paste without yanking" })

-- ============================================================================
-- Quick Access
-- ============================================================================
keymap("n", "<leader>e", "<cmd>Neotree toggle<CR>", { desc = "Toggle file explorer" })
keymap("n", "<leader>w", "<cmd>w<CR>", { desc = "Save file" })

-- Open personal cheatsheet in a horizontal split
keymap("n", "<leader>?", "<cmd>split ~/.nvimcheatsheet.md<CR>", { desc = "Cheatsheet" })

-- Format file via LSP
keymap("n", "<leader>cf", function() vim.lsp.buf.format() end, { desc = "Format file" })

-- Toggle soft wrap: word-safe (linebreak breaks at whitespace, never mid-word)
-- and non-destructive (display only, no line breaks written to the buffer).
-- Wrap point follows the window width, not a configurable column.
keymap("n", "<leader>gq", function()
  vim.wo.wrap = not vim.wo.wrap
  vim.wo.linebreak = vim.wo.wrap
end, { desc = "Toggle soft wrap (word-safe)" })

-- Note: More keymaps are defined in plugin configs (telescope, lsp, etc.)
-- Press <Space> and wait to see all available mappings via which-key
