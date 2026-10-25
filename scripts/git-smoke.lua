local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local function git(...)
  local args = { 'git', '-C', root }
  vim.list_extend(args, { ... })
  local result = vim.system(args, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return result.stdout
end
local function test()
  git('init', '-b', 'main')
  vim.fn.writefile({ 'before' }, root .. '/sample.txt')
  git('add', 'sample.txt')
  git('-c', 'user.name=Neovim Test', '-c', 'user.email=test@example.invalid', 'commit', '-m', 'Fixture')
  vim.cmd.edit(vim.fn.fnameescape(root .. '/sample.txt'))
  local gs = require 'gitsigns'
  assert(
    vim.wait(5000, function()
      return vim.b.gitsigns_head ~= nil
    end, 50),
    'Gitsigns did not attach'
  )
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'after' })
  vim.cmd 'write'
  assert(
    vim.wait(5000, function()
      return #(gs.get_hunks(vim.api.nvim_get_current_buf()) or {}) > 0
    end, 50),
    'No changed hunk'
  )
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  gs.stage_hunk()
  assert(
    vim.wait(5000, function()
      return git('diff', '--cached', '--name-only'):find('sample.txt', 1, true) ~= nil
    end, 50),
    'Hunk did not stage'
  )
  assert(
    vim.wait(5000, function()
      return #(gs.get_hunks(vim.api.nvim_get_current_buf()) or {}) == 0
    end, 50),
    'Staged hunk did not settle'
  )
  gs.stage_hunk()
  assert(
    vim.wait(5000, function()
      return git('diff', '--cached', '--name-only') == ''
    end, 50),
    'Hunk did not unstage'
  )
  print 'PASS Gitsigns attachment, change detection, staging, and unstaging'
  gs.detach_all()
end
local ok, err = xpcall(test, debug.traceback)
if not ok then
  io.stderr:write(err .. '\n')
end
vim.fn.delete(root, 'rf')
vim.cmd(ok and 'qa!' or 'cquit 1')
