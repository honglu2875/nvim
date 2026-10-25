local map = vim.keymap.set
map('n', '<Esc>', '<cmd>nohlsearch<CR>')
map('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Diagnostics list' })
map('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Diagnostic details' })
map('n', '<leader>fe', '<cmd>Explore<CR>', { desc = 'File browser' })
map('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Leave terminal mode' })
for _, direction in ipairs { 'h', 'j', 'k', 'l' } do
  map('n', '<C-' .. direction .. '>', '<C-w>' .. direction, { desc = 'Focus adjacent window' })
end
map('n', '<leader>tf', function()
  vim.b.disable_autoformat = not vim.b.disable_autoformat
  vim.notify('Format on save: ' .. (vim.b.disable_autoformat and 'off' or 'on'))
end, { desc = 'Toggle format on save' })
