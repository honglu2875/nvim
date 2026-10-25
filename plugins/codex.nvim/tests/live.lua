-- Explicit opt-in: this sends one short prompt using the existing Codex account.
assert(vim.env.CODEX_NVIM_LIVE == '1', 'Set CODEX_NVIM_LIVE=1 to run the live test')
local plugin = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)))
vim.opt.rtp:prepend(plugin)
local codex = require 'codex'
local ui = require 'codex.ui'
local temp = vim.fn.tempname()
vim.fn.mkdir(temp, 'p')
codex.setup { state_dir = false, timeout_ms = 60000, thread = { ephemeral = true, sandbox = 'read-only' } }
local function test()
  local session = codex.open(temp)
  ui.set_draft(session, 'Reply with exactly CODEX_NVIM_OK. Do not use tools or modify any files.')
  assert(codex.send(session))
  assert(
    vim.wait(120000, function()
      return not session.busy
    end, 100),
    'Live turn timed out'
  )
  assert(
    session.status == 'completed',
    'Live turn failed: ' .. vim.inspect(session.messages) .. '\n' .. tostring(codex.last_exit)
  )
  local reply = ''
  for _, message in ipairs(session.messages) do
    if message.role == 'Codex' then
      reply = reply .. message.text
    end
  end
  assert(reply:find('CODEX_NVIM_OK', 1, true), 'Unexpected live reply')
  print 'PASS real app-server initialization, thread creation, prompt, streamed reply, and completion'
end
local ok, err = xpcall(test, debug.traceback)
codex.stop()
vim.fn.delete(temp, 'rf')
if not ok then
  io.stderr:write(err .. '\n')
end
vim.cmd(ok and 'qa!' or 'cquit 1')
