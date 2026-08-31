-- ============================================================================
-- Autocompletion (nvim-cmp)
-- ============================================================================
-- Three things here are choices, the rest is nvim-cmp's own preset:
--
-- <CR> uses select = false, so Enter confirms only an item you picked on
-- purpose. Without it, a newline typed while the popup happens to be open
-- inserts the first suggestion instead.
--
-- <C-j>/<C-k> move through the list, not <C-n>/<C-p> — same direction keys as
-- everywhere else. Tab falls through in order: popup item, then snippet jump,
-- then a literal tab.
--
-- The `sources` order IS the priority order.
--
-- The autopairs hook that stops `foo(` doubling its bracket on confirm lives in
-- misc.lua, not here.
-- ============================================================================

return {
  "hrsh7th/nvim-cmp",
  event = "InsertEnter",
  dependencies = {
    "hrsh7th/cmp-nvim-lsp",     -- LSP completions
    "hrsh7th/cmp-buffer",       -- Buffer word completions
    "hrsh7th/cmp-path",         -- File path completions
    "L3MON4D3/LuaSnip",         -- Snippet engine
    "saadparwaiz1/cmp_luasnip", -- Snippet completions
    "onsails/lspkind.nvim",     -- VSCode-like icons in completion menu
  },
  config = function()
    local cmp = require("cmp")
    local luasnip = require("luasnip")
    local lspkind = require("lspkind")

    cmp.setup({
      -- Snippet expansion
      snippet = {
        expand = function(args)
          luasnip.lsp_expand(args.body)
        end,
      },

      -- Keybindings for completion menu
      mapping = cmp.mapping.preset.insert({
        -- Navigate completion items
        ["<C-k>"] = cmp.mapping.select_prev_item(),
        ["<C-j>"] = cmp.mapping.select_next_item(),

        -- Scroll docs in preview window
        ["<C-b>"] = cmp.mapping.scroll_docs(-4),
        ["<C-f>"] = cmp.mapping.scroll_docs(4),

        -- Trigger completion manually
        ["<C-Space>"] = cmp.mapping.complete(),

        -- Cancel completion
        ["<C-e>"] = cmp.mapping.abort(),

        -- Confirm selection
        ["<CR>"] = cmp.mapping.confirm({ select = false }), -- Only confirm explicitly selected items
        ["<Tab>"] = cmp.mapping(function(fallback)
          if cmp.visible() then
            cmp.select_next_item()
          elseif luasnip.expand_or_jumpable() then
            luasnip.expand_or_jump()
          else
            fallback()
          end
        end, { "i", "s" }),
        ["<S-Tab>"] = cmp.mapping(function(fallback)
          if cmp.visible() then
            cmp.select_prev_item()
          elseif luasnip.jumpable(-1) then
            luasnip.jump(-1)
          else
            fallback()
          end
        end, { "i", "s" }),
      }),

      -- Completion sources (order = priority)
      sources = cmp.config.sources({
        { name = "nvim_lsp" }, -- LSP
        { name = "luasnip" },  -- Snippets
        { name = "buffer" },   -- Buffer words
        { name = "path" },     -- File paths
      }),

      -- Appearance
      window = {
        completion = cmp.config.window.bordered(),
        documentation = cmp.config.window.bordered(),
      },

      -- VSCode-like icons
      formatting = {
        format = lspkind.cmp_format({
          mode = "symbol_text",
          maxwidth = 50,
          ellipsis_char = "...",
        }),
      },
    })
  end,
}
