-- nvim --headless -u NONE -l plugins/codex.nvim/tests/run.lua
local plugin = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)))
vim.opt.rtp:prepend(plugin)
local temp = vim.fn.tempname()
vim.fn.mkdir(temp .. '/project one/.git', 'p')
vim.fn.mkdir(temp .. '/project two/.git', 'p')
local log = temp .. '/wire.jsonl'
local notices = {}
---@diagnostic disable-next-line: duplicate-set-field -- Deliberate test replacement.
vim.notify = function(message)
  notices[#notices + 1] = message
end
local codex = require 'codex'
local ui = require 'codex.ui'
local requests = require 'codex.requests'
codex.setup {
  cmd = { 'python3', plugin .. '/tests/fake_server.py', log },
  state_dir = temp .. '/state',
  timeout_ms = 3000,
}
local function wait(predicate, label)
  assert(vim.wait(5000, predicate, 10), label .. ' timed out')
end
local function check(value, label)
  assert(value, label)
  print('PASS ' .. label)
end
local function wire()
  local result = {}
  for _, line in ipairs(vim.fn.readfile(log)) do
    result[#result + 1] = vim.json.decode(line)
  end
  return result
end

local function run()
  vim.cmd.edit(vim.fn.fnameescape(temp .. '/project one/example.py'))
  local source = vim.api.nvim_get_current_buf()
  vim.bo[source].filetype = 'python'
  vim.api.nvim_buf_set_lines(source, 0, -1, false, { 'value = "```"', 'print(value)' })
  codex.attach(1, 1)
  local first = codex.active
  check(
    ui.draft(first):find('unsaved buffer contents', 1, true) and ui.draft(first):find('````python', 1, true),
    'context preserves unsaved selection and fences'
  )
  check(not codex.rpc.job, 'opening and attaching context do not start a model request')
  ui.set_draft(first, 'Hello')
  assert(codex.send(first))
  wait(function()
    return not first.busy
  end, 'streamed turn')
  check(
    first.messages[1].role == 'You' and first.messages[2].text == 'Hello λ from Codex',
    'fragmented Unicode stream, final text and message order'
  )
  check(not first.turn and first.status == 'completed', 'early turn completion cannot resurrect a busy turn')
  check(ui.draft(first) == '', 'accepted prompt clears the unchanged draft')
  local messages = wire()
  check(
    messages[1].method == 'initialize' and messages[2].method == 'initialized' and messages[3].method == 'thread/start',
    'initialization handshake precedes thread creation'
  )
  check(
    messages[3].params.cwd == first.root
      and messages[3].params.approvalPolicy == nil
      and messages[3].params.sandbox == nil,
    'project root and configured permission policy preserved'
  )

  ui.set_draft(first, 'HOLD')
  codex.send(first)
  wait(function()
    return first.turn ~= nil
  end, 'held turn')
  check(codex.send(first) == false, 'duplicate submissions are rejected during an active turn')
  ui.hide(first)
  check(first.busy and codex.rpc.job ~= nil, 'hiding the panel keeps the conversation running')
  codex.cancel(first)
  wait(function()
    return not first.busy
  end, 'interruption')
  check(first.status == 'interrupted', 'cancellation waits for the server turn outcome')

  codex.open(first.root)
  ui.set_draft(first, 'FAIL')
  codex.send(first)
  wait(function()
    return not first.busy
  end, 'error response')
  check(ui.draft(first) == 'FAIL' and first.status == 'error', 'server errors preserve the draft for correction')

  vim.cmd.wincmd 'h'
  vim.cmd.edit(vim.fn.fnameescape(temp .. '/project two/example.py'))
  codex.ask 'second project'
  local second = codex.active
  codex.send(second)
  wait(function()
    return not second.busy
  end, 'second project')
  check(first.thread ~= second.thread and first.root ~= second.root, 'projects have separate threads')
  ui.set_draft(first, 'first project again')
  vim.api.nvim_set_current_win(ui.get(first).input_win)
  codex.send()
  wait(function()
    return not first.busy
  end, 'focus routing')
  check(
    first.messages[#first.messages - 1].text == 'first project again',
    'commands route to the focused panel, not the last opened project'
  )

  local replied, choose_callback, choices
  ---@return {id: any, result: any, error: any}
  local function reply()
    return assert(replied, 'Expected a server-request response')
  end
  local peer = {
    reply = function(_, id, result, err)
      replied = { id = id, result = result, error = err }
    end,
  }
  ---@diagnostic disable-next-line: duplicate-set-field -- Deliberate test replacement.
  vim.ui.select = function(items, _, cb)
    choices, choose_callback = items, cb
  end
  requests.handle({
    id = 'approval',
    method = 'item/commandExecution/requestApproval',
    params = {
      threadId = first.thread,
      turnId = 'approval-turn',
      command = 'git status',
      networkApprovalContext = vim.NIL,
    },
  }, peer)
  check(replied == nil and vim.tbl_contains(choices, 'Allow once'), 'approval is pending until an explicit user choice')
  choose_callback(nil)
  check(reply().result.decision == 'cancel', 'dismissing an approval never grants access')
  wait(function()
    return requests.active == nil
  end, 'approval cleanup')
  replied = nil
  requests.handle({ id = 0, method = 'item/fileChange/requestApproval', params = {} }, peer, 'example.py\n-old\n+new')
  choose_callback 'Allow once'
  check(reply().id == 0 and reply().result.decision == 'accept', 'explicit file approval and numeric zero request ids')
  wait(function()
    return requests.active == nil
  end, 'file approval cleanup')
  replied = nil
  requests.handle({ id = 'stale', method = 'item/fileChange/requestApproval', params = {} }, peer)
  requests.resolved 'stale'
  choose_callback 'Allow once'
  check(replied == nil, 'resolved requests ignore late UI answers')
  wait(function()
    return requests.active == nil
  end, 'stale approval cleanup')
  requests.handle({
    id = 'permission',
    method = 'item/permissions/requestApproval',
    params = { permissions = { network = { enabled = true } } },
  }, peer)
  choose_callback 'Decline'
  check(
    vim.tbl_isempty(reply().result.permissions) and reply().result.scope == 'turn',
    'permission denial grants no capabilities'
  )
  wait(function()
    return requests.active == nil
  end, 'permission cleanup')
  requests.handle({
    id = 'question',
    method = 'item/tool/requestUserInput',
    params = {
      questions = {
        {
          id = 'q1',
          header = 'Choice',
          question = 'Which?',
          options = { { label = 'A', description = 'first' }, { label = 'B', description = 'second' } },
        },
      },
    },
  }, peer)
  choose_callback(choices[2])
  check(reply().result.answers.q1.answers[1] == 'B', 'structured user answers retain question ids')
  wait(function()
    return requests.active == nil
  end, 'question cleanup')

  ui.set_draft(first, 'UNKNOWN')
  codex.send(first)
  wait(function()
    return not first.busy
  end, 'unsupported request')
  wait(function()
    for _, message in ipairs(wire()) do
      if message.id == 'unknown-1' and message.error and message.error.code == -32601 then
        return true
      end
    end
  end, 'unsupported method reply')
  check(true, 'unknown server requests receive an error instead of hanging')

  codex.rpc.opts.timeout_ms = 40
  local timeout
  codex.rpc:request('never', {}, function(err)
    timeout = err
  end)
  wait(function()
    return timeout ~= nil
  end, 'timeout')
  check(timeout.message:find('timed out', 1, true), 'lost responses terminate with an actionable timeout')
  codex.rpc.opts.timeout_ms = 3000
  local lost
  codex.rpc:request('never', {}, function(err)
    lost = err
  end)
  codex.rpc:request('crash', {}, function() end)
  wait(function()
    return not codex.rpc.job
  end, 'crash')
  check(
    lost and not first.busy and first.status == 'disconnected',
    'process exit clears pending requests and active state'
  )
  codex.open(first.root)
  codex.resume()
  wait(function()
    return not first.busy and first.thread ~= nil
  end, 'resume')
  check(first.messages[1].text == 'Restored history', 'saved project thread resumes after server restart')
  codex.stop()
end

local ok, err = xpcall(run, debug.traceback)
codex.stop()
if not ok then
  io.stderr:write(err .. '\nTest artifacts: ' .. temp .. '\n')
else
  vim.fn.delete(temp, 'rf')
end
vim.cmd(ok and 'qa!' or 'cquit 1')
