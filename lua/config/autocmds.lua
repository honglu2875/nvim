local group = vim.api.nvim_create_augroup('personal-editor', { clear = true })
vim.api.nvim_create_autocmd('TextYankPost', {
  group = group,
  callback = function()
    vim.hl.on_yank()
  end,
})
vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter' }, {
  group = group,
  callback = function()
    if vim.bo.buftype == '' then
      vim.cmd 'checktime'
    end
  end,
})
