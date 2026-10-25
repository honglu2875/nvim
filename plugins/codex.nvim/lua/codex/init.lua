local M = { sessions = {}, by_thread = {} }
local ui = require 'codex.ui'
local context = require 'codex.context'
local requests = require 'codex.requests'
local defaults = {
  cmd = { 'codex', 'app-server', '--listen', 'stdio://' },
  width = 0.45,
  input_height = 7,
  max_context_bytes = 100 * 1024,
  timeout_ms = 30000,
  thread = {}, -- Omitted model, auth, and permission settings follow Codex configuration.
}

local function append(session, role, text, id)
  local message = { role = role, text = text, id = id }
  session.messages[#session.messages + 1] = message
  if id then
    session.items[id] = message
  end
  ui.update(session)
  return message
end

local function fail(session, err)
  local text = type(err) == 'table' and (err.message or vim.inspect(err)) or tostring(err)
  session.status = 'error'
  append(session, 'Error', text)
  vim.notify('Codex: ' .. text, vim.log.levels.ERROR)
end

local function session_for(root)
  root = root or ui.root(vim.api.nvim_get_current_buf()) or context.root(vim.api.nvim_get_current_buf())
  if not M.sessions[root] then
    M.sessions[root] = { root = root, messages = {}, items = {}, completed = {}, status = 'ready' }
  end
  return M.sessions[root]
end

local function state_path(session)
  if M.opts.state_dir == false then
    return
  end
  return (M.opts.state_dir or vim.fn.stdpath 'state' .. '/codex') .. '/' .. vim.fn.sha256(session.root) .. '.json'
end

local function remember(session)
  local path = state_path(session)
  if not path or M.opts.thread.ephemeral then
    return
  end
  -- Neovim 0.12's Lua annotation incorrectly calls the numeric mode a string.
  local mkdir = vim.fn.mkdir --[[@as fun(name: string, flags: string, mode: integer): integer]]
  mkdir(vim.fs.dirname(path), 'p', 448)
  local temporary = path .. '.' .. vim.fn.getpid() .. '.tmp'
  vim.fn.writefile({ vim.json.encode { root = session.root, thread_id = session.thread } }, temporary)
  vim.uv.fs_chmod(temporary, 384)
  assert(vim.uv.fs_rename(temporary, path))
end

local function item(session, value, historical)
  local kind, text = value.type, nil
  if kind == 'agentMessage' then
    text = value.text or ''
  elseif kind == 'userMessage' and historical then
    local parts = {}
    for _, part in ipairs(value.content or {}) do
      if part.type == 'text' then
        parts[#parts + 1] = part.text
      end
    end
    text = table.concat(parts, '\n')
  elseif kind == 'commandExecution' then
    text = ('```sh\n%s\n```\nDirectory: %s\nStatus: %s'):format(
      value.command or '',
      value.cwd or '',
      value.status or ''
    )
    if type(value.aggregatedOutput) == 'string' and value.aggregatedOutput ~= '' then
      text = text .. '\n\n```text\n' .. value.aggregatedOutput:sub(-16000) .. '\n```'
    end
  elseif kind == 'fileChange' then
    local changes, patches = {}, {}
    for _, change in ipairs(value.changes or {}) do
      changes[#changes + 1] = change.path or ''
      patches[#patches + 1] = (change.path or '') .. '\n' .. (change.diff or '')
    end
    text = 'Status: ' .. (value.status or '') .. '\n' .. table.concat(changes, '\n')
    session.latest_diff = table.concat(patches, '\n\n')
    session.file_changes = session.file_changes or {}
    session.file_changes[value.id] = session.latest_diff
  elseif kind == 'mcpToolCall' or kind == 'webSearch' or kind == 'dynamicToolCall' then
    text = (value.tool or value.type) .. ': ' .. (value.status or '')
  end
  if text == nil then
    return
  end
  local message = session.items[value.id]
  if message then
    message.text = text
    ui.update(session)
  else
    append(session, kind == 'agentMessage' and 'Codex' or kind == 'userMessage' and 'You' or kind, text, value.id)
  end
end

function M.on_notification(method, params)
  if method == 'serverRequest/resolved' then
    requests.resolved(params.requestId)
    return
  end
  local session = M.by_thread[params.threadId]
  if not session then
    return
  end
  if method == 'item/agentMessage/delta' then
    local message = session.items[params.itemId] or append(session, 'Codex', '', params.itemId)
    message.text = message.text .. params.delta
    ui.update(session)
  elseif method == 'item/started' or method == 'item/completed' then
    item(session, params.item)
  elseif method == 'turn/started' then
    if not session.completed[params.turn.id] then
      session.turn, session.busy, session.status = params.turn.id, true, 'working'
      if session.cancel_pending then
        M.cancel(session)
      end
    end
  elseif method == 'turn/completed' then
    requests.cancel_turn(params.threadId, params.turn.id)
    session.completed[params.turn.id] = true
    session.turn, session.busy, session.cancel_pending = nil, session.submitting or false, nil
    session.status = params.turn.status
    for _, value in ipairs(params.turn.items or {}) do
      item(session, value)
    end
    if type(params.turn.error) == 'table' then
      fail(session, params.turn.error)
    end
    vim.schedule(function()
      pcall(function()
        vim.cmd 'checktime'
      end)
    end)
  elseif method == 'turn/diff/updated' then
    session.latest_diff = params.diff
  elseif method == 'error' then
    fail(session, params.error)
  end
  ui.update(session)
end

local function with_thread(session, done, resume_id)
  if session.thread and not resume_id then
    done()
    return
  end
  M.rpc:start(function(err)
    if err then
      done(err)
      return
    end
    local params = vim.tbl_deep_extend('force', {}, M.opts.thread, { cwd = session.root })
    if resume_id then
      params.threadId = resume_id
      params.excludeTurns = false
      params.ephemeral = nil
    end
    M.rpc:request(resume_id and 'thread/resume' or 'thread/start', params, function(error, result)
      if error then
        done(error)
        return
      end
      if session.thread then
        M.by_thread[session.thread] = nil
      end
      session.thread = result.thread.id
      M.by_thread[session.thread] = session
      local saved, save_error = pcall(remember, session)
      if not saved then
        vim.notify('Unable to save Codex thread id: ' .. tostring(save_error), vim.log.levels.WARN)
      end
      if resume_id then
        session.messages, session.items, session.completed = {}, {}, {}
        for _, turn in ipairs(result.thread.turns or {}) do
          for _, value in ipairs(turn.items or {}) do
            item(session, value, true)
          end
          if turn.status == 'inProgress' then
            session.turn, session.busy = turn.id, true
          end
        end
      end
      done()
    end)
  end)
end

function M.open(root)
  local session = session_for(root)
  M.active = session
  ui.open(session, M.opts, {
    send = function()
      M.send(session)
    end,
    cancel = function()
      M.cancel(session)
    end,
  })
  return session
end

function M.toggle()
  local session = session_for()
  if ui.visible(session) then
    ui.hide(session)
  else
    M.open(session.root)
  end
end

function M.send(session)
  session = session or session_for()
  if session.busy then
    vim.notify 'Codex is working; cancel the turn before sending another prompt'
    return false
  end
  local text = ui.draft(session)
  if vim.trim(text) == '' then
    return false
  end
  session.busy, session.status = true, 'connecting'
  ui.update(session)
  with_thread(session, function(err)
    if err then
      session.busy = false
      fail(session, err)
      return
    end
    if session.cancel_pending then
      session.cancel_pending, session.busy, session.status = nil, false, 'cancelled before send'
      ui.update(session)
      return
    end
    append(session, 'You', text)
    session.submitting = true
    M.rpc:request(
      'turn/start',
      { threadId = session.thread, input = { { type = 'text', text = text } } },
      function(error, result)
        session.submitting = nil
        if error then
          -- Keep the draft on failures. A timeout may have created a live turn.
          if not session.turn then
            session.busy = false
          end
          fail(session, error)
          return
        end
        if ui.draft(session) == text then
          ui.set_draft(session, '')
        end
        if not session.completed[result.turn.id] then
          session.turn, session.busy, session.status = result.turn.id, true, 'working'
          if session.cancel_pending then
            M.cancel(session)
          end
        else
          session.busy, session.cancel_pending = false, nil
        end
        ui.update(session)
      end
    )
  end)
  return true
end

function M.cancel(session)
  session = session or session_for()
  if not session.busy then
    return
  end
  if not session.turn then
    session.cancel_pending = true
    return
  end
  session.cancel_pending = nil
  session.status = 'cancelling'
  M.rpc:request('turn/interrupt', { threadId = session.thread, turnId = session.turn }, function(err)
    if err then
      fail(session, err)
    end
  end)
  ui.update(session)
end

function M.ask(text)
  local session = M.open()
  ui.set_draft(session, text)
end

function M.attach(first, last)
  local buf = vim.api.nvim_get_current_buf()
  local ok, text = pcall(context.capture, buf, first, last, M.opts.max_context_bytes)
  if not ok then
    vim.notify(tostring(text), vim.log.levels.WARN)
    return
  end
  local session = M.open(context.root(buf))
  local draft = ui.draft(session)
  ui.set_draft(session, draft .. (draft ~= '' and '\n\n' or '') .. text .. '\n\n')
end

function M.new()
  local session = session_for()
  if session.busy then
    vim.notify 'Cancel the current turn before starting a new chat'
    return
  end
  if session.thread then
    M.by_thread[session.thread] = nil
  end
  session.thread, session.messages, session.items, session.completed = nil, {}, {}, {}
  session.latest_diff, session.file_changes = nil, nil
  session.status = 'ready'
  M.open(session.root)
  ui.render(session)
end

function M.resume(id)
  local session = session_for()
  if session.busy then
    vim.notify 'Cancel the current turn before resuming another chat'
    return
  end
  if not id or id == '' then
    local path = state_path(session)
    if not path then
      vim.notify 'Saved-thread indexing is disabled; supply a thread id to resume'
      return
    end
    local ok, saved = pcall(function()
      return vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
    end)
    if not ok then
      vim.notify 'No saved Codex thread for this project'
      return
    end
    id = saved.thread_id
  end
  session.busy, session.status = true, 'resuming'
  M.open(session.root)
  with_thread(session, function(err)
    session.busy = session.turn ~= nil
    if err then
      fail(session, err)
    else
      session.status = session.busy and 'working' or 'ready'
      ui.update(session)
    end
  end, id)
end

function M.review()
  local session = session_for()
  ui.review('Codex changes · q to close', session.latest_diff or 'No changes reported for this conversation.')
end

function M.stop()
  requests.clear()
  if M.rpc then
    M.rpc:stop()
  end
end

function M.setup(opts)
  if M.rpc then
    M.stop()
  end
  M.opts = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  assert(type(M.opts.cmd) == 'table' and #M.opts.cmd > 0, 'Codex cmd must be an argument list')
  M.rpc = require('codex.rpc').new {
    cmd = M.opts.cmd,
    timeout_ms = M.opts.timeout_ms,
    on_notification = M.on_notification,
    on_request = function(message, rpc)
      local session = M.by_thread[message.params.threadId]
      local details = session and session.file_changes and session.file_changes[message.params.itemId]
      requests.handle(message, rpc, details)
    end,
    on_error = function(err)
      vim.notify(err, vim.log.levels.ERROR)
    end,
    on_exit = function(reason)
      requests.clear()
      for _, session in pairs(M.sessions) do
        session.busy, session.turn, session.status, session.submitting = false, nil, 'disconnected', nil
        -- Resume the persisted thread explicitly after reconnecting.
        session.thread = nil
        ui.update(session)
      end
      M.by_thread = {}
      M.last_exit = reason
    end,
  }
  local function command(name, fn, config)
    vim.api.nvim_create_user_command(name, fn, config or {})
  end
  command('Codex', M.toggle, { desc = 'Toggle the Codex chat panel' })
  command('CodexAsk', function(args)
    M.ask(args.args)
  end, { nargs = '*', desc = 'Draft a Codex prompt' })
  command('CodexContext', function(args)
    M.attach(args.range > 0 and args.line1 or nil, args.range > 0 and args.line2 or nil)
  end, { range = true, desc = 'Attach buffer or selected lines to the draft' })
  command('CodexSend', function()
    M.send()
  end, { desc = 'Send the draft' })
  command('CodexCancel', function()
    M.cancel()
  end, { desc = 'Interrupt the active turn' })
  command('CodexNew', M.new, { desc = 'Start a new conversation' })
  command('CodexResume', function(args)
    M.resume(args.args)
  end, { nargs = '?', desc = 'Resume a saved thread' })
  command('CodexReview', M.review, { desc = 'Inspect reported changes' })
  command('CodexStop', M.stop, { desc = 'Stop the app-server process' })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = vim.api.nvim_create_augroup('personal-codex', { clear = true }),
    callback = M.stop,
  })
end

return M
