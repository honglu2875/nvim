return {
  {
    'neovim/nvim-lspconfig',
    dependencies = {
      { 'mason-org/mason.nvim', opts = {} },
      'mason-org/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',
      'saghen/blink.cmp',
    },
    config = function()
      local tools = require 'config.tools'
      vim.lsp.config('*', { capabilities = require('blink.cmp').get_lsp_capabilities() })
      vim.lsp.config('clangd', { filetypes = { 'c', 'cpp' } })
      vim.lsp.config('lua_ls', { settings = { Lua = { completion = { callSnippet = 'Disable' } } } })
      vim.lsp.config('ruff', {
        on_attach = function(client)
          client.server_capabilities.hoverProvider = false -- ty owns semantic hover.
        end,
      })
      require('mason-lspconfig').setup {
        ensure_installed = tools.servers,
        automatic_enable = tools.servers,
      }
      require('mason-tool-installer').setup {
        ensure_installed = tools.packages,
        auto_update = false,
      }
      vim.diagnostic.config { severity_sort = true, float = { source = true }, virtual_text = false }
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('personal-lsp', { clear = true }),
        callback = function(event)
          local function map(key, fn, desc, mode)
            vim.keymap.set(mode or 'n', key, fn, { buffer = event.buf, desc = desc })
          end
          local builtin = require 'telescope.builtin'
          map('gd', builtin.lsp_definitions, 'Definitions')
          map('grr', builtin.lsp_references, 'References')
          map('gI', builtin.lsp_implementations, 'Implementations')
          map('gD', vim.lsp.buf.declaration, 'Declaration')
          map('<leader>D', builtin.lsp_type_definitions, 'Type definition')
          map('<leader>ds', builtin.lsp_document_symbols, 'Document symbols')
          map('<leader>ws', builtin.lsp_dynamic_workspace_symbols, 'Workspace symbols')
          map('<leader>rn', vim.lsp.buf.rename, 'Rename')
          map('<leader>ca', vim.lsp.buf.code_action, 'Code action', { 'n', 'x' })
          map('<leader>th', function()
            vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf }, { bufnr = event.buf })
          end, 'Toggle inlay hints')
        end,
      })
    end,
  },
  {
    'Julian/lean.nvim',
    event = { 'BufReadPre *.lean', 'BufNewFile *.lean' },
    dependencies = { 'neovim/nvim-lspconfig', 'nvim-lua/plenary.nvim' },
    init = function()
      vim.g.lean_config = { mappings = true }
    end,
  },
}
