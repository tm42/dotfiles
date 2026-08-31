-- ============================================================================
-- Core Neovim Options
-- ============================================================================
-- These settings configure Neovim's built-in behavior.
-- No plugins required - these are all native Neovim features.
-- ============================================================================

local opt = vim.opt

-- Line Numbers
opt.number = true         -- Show line numbers
opt.relativenumber = true -- Show relative numbers (great for jumping: 5j, 10k)

-- Tabs & Indentation
opt.tabstop = 4           -- Tab displays as 4 spaces
opt.shiftwidth = 4        -- Indent with 4 spaces
opt.expandtab = true      -- Convert tabs to spaces
opt.autoindent = true     -- Copy indent from current line
opt.smartindent = true    -- Smart autoindenting on new lines

-- Search
opt.ignorecase = true     -- Ignore case when searching...
opt.smartcase = true      -- ...unless you use uppercase
opt.hlsearch = true       -- Highlight search results
opt.incsearch = true      -- Show matches as you type

-- Appearance
opt.termguicolors = true  -- Enable 24-bit RGB colors
opt.signcolumn = "yes"    -- Always show sign column (prevents layout shift)
opt.cursorline = true     -- Highlight the current line
opt.scrolloff = 5         -- Keep 5 lines visible above/below cursor
opt.sidescrolloff = 5     -- Keep 5 columns visible left/right of cursor
opt.wrap = false          -- Don't wrap long lines

-- Window Splits
opt.splitright = true     -- Vertical splits open to the right
opt.splitbelow = true     -- Horizontal splits open below

-- Behavior
opt.mouse = "a"           -- Enable mouse in all modes
opt.clipboard = "unnamedplus" -- Use system clipboard
opt.undofile = true       -- Persistent undo (survives closing file)
opt.swapfile = false      -- Disable swap files
opt.updatetime = 250      -- Faster completion (default is 4000ms)
opt.timeoutlen = 300      -- Time to wait for mapped sequence (ms)

-- Completion
opt.completeopt = "menuone,noselect" -- Better completion experience
opt.pumheight = 10        -- Maximum items in popup menu

-- File encoding
opt.encoding = "utf-8"
opt.fileencoding = "utf-8"

-- Show invisible characters (optional - uncomment if you want)
-- opt.list = true
-- opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

-- ============================================================================
-- tmux tab label
-- ============================================================================
-- Publishes "<repo>/<file>" as the terminal title so ~/.tmux.conf's @tab can
-- render "✎:punto/options.lua". nvim sets no title by default, which is why
-- those tabs fell through to @tab's last branch and showed the cwd basename.
--
-- Truncation happens here, not in tmux. tmux's #{=/-N/…:} can only blind-cut a
-- tail, which eats the repo name whole; shrinking each half against its own
-- budget keeps both readable. @tab still wraps this in #{=/-37/…:} as a
-- backstop for titles we did not write — a stale one, or another vim-ish
-- program — so the 40-cell cap holds either way.
--
-- CAP is 37 to match that backstop exactly: at 37 the backstop never trims, so
-- it never appends a second "…". Raising one without the other doubles it up.

opt.title = true

-- ============================================================================
-- Create missing parent directories on write
-- ============================================================================
-- :w into a directory that does not exist yet fails with E212. The path was
-- typed deliberately (see <leader>ns in keymaps.lua), so create the parent
-- rather than making the user drop out to :!mkdir -p and write again.
vim.api.nvim_create_autocmd("BufWritePre", {
  group = vim.api.nvim_create_augroup("MkdirOnWrite", { clear = true }),
  callback = function(ev)
    -- Scheme-prefixed buffers (fugitive://, oil://) write through their own
    -- handler; their "directory" is not a path on disk.
    if ev.match:match("^%w%w+://") then return end
    local dir = vim.fn.fnamemodify(ev.match, ":p:h")
    if vim.fn.isdirectory(dir) == 0 then vim.fn.mkdir(dir, "p") end
  end,
})

local CAP      = 37   -- cells for the label, i.e. 40 minus the "✎:" tmux adds
local REPO_MIN = 8    -- floor for a squeezed repo, below which it is noise

-- Last n cells of s, marked with a leading "…". strdisplaywidth, not #s: the
-- budget is terminal cells, and CJK is two of them per character.
local function tail(s, n)
  local w = vim.fn.strdisplaywidth
  if w(s) <= n then return s end
  for i = 1, vim.fn.strchars(s) do
    local part = vim.fn.strcharpart(s, i)
    if w(part) <= n - 1 then return "…" .. part end
  end
  return "…"
end

local function tab_label()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then return "[No Name]" end

  local w    = vim.fn.strdisplaywidth
  local file = vim.fn.fnamemodify(path, ":t")
  local root = vim.fs.root(path, ".git")   -- matches .git as file too, so a
  if not root then return tail(file, CAP) end   -- submodule wins over its parent

  local repo = vim.fs.basename(root)
  if w(repo) + 1 + w(file) <= CAP then return repo .. "/" .. file end

  -- Squeeze the repo first — the filename is the half worth keeping intact.
  local r = tail(repo, math.max(REPO_MIN, CAP - 1 - w(file)))
  return r .. "/" .. tail(file, CAP - 1 - w(r))
end

vim.api.nvim_create_autocmd({ "BufEnter", "BufFilePost", "WinEnter", "VimEnter" }, {
  group = vim.api.nvim_create_augroup("TmuxTabLabel", { clear = true }),
  callback = function()
    -- Skip neo-tree, help, terminals and the like: the tab should keep naming
    -- the last real file while you are off in a sidebar.
    if vim.bo.buftype ~= "" then return end
    -- titlestring is a statusline format, so a literal % in a filename would be
    -- read as an item and silently mangle the label.
    vim.o.titlestring = tab_label():gsub("%%", "%%%%")
    -- tmux repaints the status bar on its own interval; nudge it so the tab
    -- tracks :e immediately rather than up to status-interval seconds later.
    if vim.env.TMUX then vim.system({ "tmux", "refresh-client", "-S" }, { detach = true }) end
  end,
})
