return {
  {
    'lewis6991/gitsigns.nvim',
    opts = {
      signs = {
        add = { text = '+' },
        change = { text = '~' },
        delete = { text = '_' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
      },
      on_attach = function(buf)
        local gs = require 'gitsigns'
        local function map(key, fn, desc, mode)
          vim.keymap.set(mode or 'n', key, fn, { buffer = buf, desc = desc })
        end
        map(']c', function()
          if vim.wo.diff then
            vim.cmd.normal { ']c', bang = true }
          else
            gs.nav_hunk 'next'
          end
        end, 'Next change')
        map('[c', function()
          if vim.wo.diff then
            vim.cmd.normal { '[c', bang = true }
          else
            gs.nav_hunk 'prev'
          end
        end, 'Previous change')
        map('<leader>hs', gs.stage_hunk, 'Stage/unstage hunk')
        map('<leader>hr', gs.reset_hunk, 'Reset hunk')
        map('<leader>hp', gs.preview_hunk, 'Preview hunk')
        map('<leader>hb', function()
          gs.blame_line { full = true }
        end, 'Blame line')
        map('<leader>hd', gs.diffthis, 'Diff against index')
        map('<leader>tb', gs.toggle_current_line_blame, 'Toggle line blame')
        map('<leader>hs', function()
          gs.stage_hunk { vim.fn.line '.', vim.fn.line 'v' }
        end, 'Stage selection', 'x')
        map('<leader>hr', function()
          gs.reset_hunk { vim.fn.line '.', vim.fn.line 'v' }
        end, 'Reset selection', 'x')
      end,
    },
  },
}
