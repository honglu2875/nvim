return {
  'tpope/vim-sleuth',
  {
    'nvim-mini/mini.nvim',
    config = function()
      require('mini.ai').setup { n_lines = 500 }
      require('mini.surround').setup()
      require('mini.statusline').setup { use_icons = vim.g.have_nerd_font }
    end,
  },
  {
    'folke/which-key.nvim',
    event = 'VeryLazy',
    opts = {
      spec = {
        { '<leader>s', group = 'Search' },
        { '<leader>c', group = 'Code', mode = { 'n', 'x' } },
        { '<leader>a', group = 'Codex', mode = { 'n', 'x' } },
        { '<leader>h', group = 'Git hunk', mode = { 'n', 'x' } },
        { '<leader>t', group = 'Toggle' },
      },
    },
  },
  {
    'folke/flash.nvim',
    opts = { modes = { char = { enabled = false }, search = { enabled = false } } },
    keys = {
      {
        '<leader>j',
        function()
          require('flash').jump()
        end,
        mode = { 'n', 'x', 'o' },
        desc = 'Flash jump',
      },
      {
        '<leader>J',
        function()
          require('flash').treesitter()
        end,
        mode = { 'n', 'x', 'o' },
        desc = 'Flash syntax node',
      },
    },
  },
  -- Preserve the existing Copilot plugin and its default mappings.
  'github/copilot.vim',
}
