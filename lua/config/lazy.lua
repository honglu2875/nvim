local path = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(path) then
  local result = vim
    .system({
      'git',
      'clone',
      '--filter=blob:none',
      '--branch=stable',
      'https://github.com/folke/lazy.nvim.git',
      path,
    }, { text = true })
    :wait()
  assert(result.code == 0, 'Unable to install lazy.nvim: ' .. (result.stderr or ''))
end
vim.opt.rtp:prepend(path)
require('lazy').setup({ { import = 'plugins' } }, {
  checker = { enabled = false },
  change_detection = { notify = false },
})
