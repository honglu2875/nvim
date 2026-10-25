return {
  {
    'stevearc/conform.nvim',
    event = 'BufWritePre',
    cmd = 'ConformInfo',
    keys = {
      {
        '<leader>f',
        function()
          require('conform').format { async = true, lsp_format = 'fallback' }
        end,
        mode = { 'n', 'x' },
        desc = 'Format',
      },
    },
    opts = {
      formatters_by_ft = {
        python = { 'ruff_format' },
        javascript = { 'prettier' },
        javascriptreact = { 'prettier' },
        typescript = { 'prettier' },
        typescriptreact = { 'prettier' },
        go = { 'gofmt' },
        rust = { 'rustfmt' },
        lua = { 'stylua' },
        c = { 'clang_format' },
        cpp = { 'clang_format' },
      },
      format_on_save = function(buf)
        if vim.b[buf].disable_autoformat or vim.bo[buf].buftype ~= '' then
          return
        end
        -- Preserve the previous opt-in policy for C/C++; manual formatting works.
        if vim.bo[buf].filetype == 'c' or vim.bo[buf].filetype == 'cpp' then
          return
        end
        return { timeout_ms = 3000, lsp_format = 'fallback' }
      end,
    },
  },
}
