return {
  {
    dir = vim.fn.stdpath 'config' .. '/plugins/codex.nvim',
    name = 'personal-codex.nvim',
    lazy = false,
    main = 'codex',
    opts = {
      width = 0.45,
      input_height = 7,
      -- thread = { model = 'your-preferred-model' },
      -- Otherwise model and permissions follow your existing Codex configuration.
    },
    keys = {
      { '<leader>aa', '<cmd>Codex<CR>', desc = 'Codex chat' },
      { '<leader>ac', '<cmd>CodexContext<CR>', desc = 'Attach buffer to Codex' },
      { '<leader>ac', ':CodexContext<CR>', mode = 'x', desc = 'Attach selection to Codex' },
      { '<leader>ax', '<cmd>CodexCancel<CR>', desc = 'Cancel Codex turn' },
      { '<leader>an', '<cmd>CodexNew<CR>', desc = 'New Codex conversation' },
      { '<leader>ar', '<cmd>CodexResume<CR>', desc = 'Resume Codex conversation' },
      { '<leader>ad', '<cmd>CodexReview<CR>', desc = 'Review Codex changes' },
    },
  },
}
