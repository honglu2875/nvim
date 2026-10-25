return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false,
    build = ':TSUpdate',
    dependencies = { 'mason-org/mason.nvim' },
    config = function()
      require('nvim-treesitter').setup()
      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('personal-treesitter', { clear = true }),
        callback = function(event)
          if vim.bo[event.buf].buftype ~= '' then
            return
          end
          local lang = vim.treesitter.language.get_lang(vim.bo[event.buf].filetype)
          local ok, loaded = pcall(vim.treesitter.language.add, lang or '')
          if ok and loaded then
            vim.treesitter.start(event.buf, lang)
          end
        end,
      })
      vim.api.nvim_create_user_command('ParsersInstall', function()
        require('nvim-treesitter').install(require('config.tools').parsers)
      end, { desc = 'Install the configured language parsers' })
    end,
  },
}
