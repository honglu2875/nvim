vim.cmd 'checkhealth'
local path = vim.env.NVIM_HEALTH_REPORT or vim.fn.stdpath 'state' .. '/health-report.txt'
vim.fn.writefile(vim.api.nvim_buf_get_lines(0, 0, -1, false), path)
print('Health report: ' .. path)
vim.cmd 'qa!'
