return {
  {
    'nvim-telescope/telescope.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-tree/nvim-web-devicons',
      { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
      'nvim-telescope/telescope-ui-select.nvim',
    },
    config = function()
      local telescope = require 'telescope'
      telescope.setup { extensions = { ['ui-select'] = { require('telescope.themes').get_dropdown() } } }
      telescope.load_extension 'fzf'
      telescope.load_extension 'ui-select'
      local builtin = require 'telescope.builtin'
      for key, spec in pairs {
        sf = { builtin.find_files, 'Files' },
        sg = { builtin.live_grep, 'Grep' },
        sw = { builtin.grep_string, 'Word' },
        sh = { builtin.help_tags, 'Help' },
        sk = { builtin.keymaps, 'Keymaps' },
        sd = { builtin.diagnostics, 'Diagnostics' },
        sr = { builtin.resume, 'Resume search' },
        ['s.'] = { builtin.oldfiles, 'Recent files' },
        ['<space>'] = { builtin.buffers, 'Buffers' },
      } do
        vim.keymap.set('n', '<leader>' .. key, spec[1], { desc = spec[2] })
      end
      vim.keymap.set('n', '<leader>sn', function()
        builtin.find_files { cwd = vim.fn.stdpath 'config' }
      end, { desc = 'Configuration files' })
      vim.keymap.set('n', '<leader>/', function()
        builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown { previewer = false })
      end, { desc = 'Search current buffer' })
    end,
  },
}
