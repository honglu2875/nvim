-- Newline-delimited, bidirectional app-server RPC over a local child process.
local Rpc = {}
Rpc.__index = Rpc

function Rpc.new(opts)
  return setmetatable({ opts = opts, pending = {}, waiting = {}, next_id = 0, tail = '', stderr = '' }, Rpc)
end

local function callback(fn, ...)
  if not fn then
    return
  end
  local ok, err = pcall(fn, ...)
  if not ok then
    vim.schedule(function()
      vim.notify('Codex callback: ' .. tostring(err), vim.log.levels.ERROR)
    end)
  end
end

local function close_timer(timer)
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
end

function Rpc:send(message)
  if not self.job then
    return false, 'Codex app-server is not running'
  end
  local ok, err = pcall(vim.fn.chansend, self.job, vim.json.encode(message) .. '\n')
  return ok, err
end

function Rpc:notify(method, params)
  return self:send { method = method, params = params or vim.empty_dict() }
end

function Rpc:reply(id, result, err)
  local message = { id = id }
  if err then
    message.error = err
  else
    message.result = result or vim.empty_dict()
  end
  return self:send(message)
end

function Rpc:request(method, params, fn)
  self.next_id = self.next_id + 1
  local id = self.next_id
  local timer = assert(vim.uv.new_timer())
  self.pending[id] = { callback = fn, timer = timer }
  timer:start(
    self.opts.timeout_ms or 30000,
    0,
    vim.schedule_wrap(function()
      local pending = self.pending[id]
      if not pending then
        return
      end
      self.pending[id] = nil
      close_timer(timer)
      callback(fn, { message = method .. ' timed out; the server may still be processing it' })
    end)
  )
  local ok, err = self:send { id = id, method = method, params = params or vim.empty_dict() }
  if not ok then
    self.pending[id] = nil
    close_timer(timer)
    callback(fn, { message = tostring(err) })
  end
  return id
end

function Rpc:receive(message)
  if type(message) ~= 'table' then
    return
  end
  if message.method then
    if message.id ~= nil then
      if self.opts.on_request then
        callback(self.opts.on_request, message, self)
      else
        self:reply(message.id, nil, { code = -32601, message = 'Unsupported client request: ' .. message.method })
      end
    else
      callback(self.opts.on_notification, message.method, message.params or {})
    end
  elseif message.id ~= nil then
    local pending = self.pending[message.id]
    if not pending then
      return
    end
    self.pending[message.id] = nil
    close_timer(pending.timer)
    local err = message.error ~= vim.NIL and message.error or nil
    callback(pending.callback, err, message.result)
  end
end

function Rpc:consume(data)
  local text = self.tail .. table.concat(data, '\n')
  local start = 1
  while true do
    local finish = text:find('\n', start, true)
    if not finish then
      break
    end
    local line = text:sub(start, finish - 1)
    start = finish + 1
    if line ~= '' then
      local ok, message = pcall(vim.json.decode, line)
      if ok then
        self:receive(message)
      else
        callback(self.opts.on_error, 'Invalid JSON from Codex app-server')
      end
    end
  end
  self.tail = text:sub(start)
  if #self.tail > 16 * 1024 * 1024 then
    callback(self.opts.on_error, 'Codex app-server exceeded the message size limit')
    self:stop()
  end
end

function Rpc:finish(reason)
  self.ready, self.job = false, nil
  local pending, waiting = self.pending, self.waiting
  self.pending, self.waiting = {}, {}
  for _, request in pairs(pending) do
    close_timer(request.timer)
    callback(request.callback, { message = reason })
  end
  for _, fn in ipairs(waiting) do
    callback(fn, { message = reason })
  end
  callback(self.opts.on_exit, reason)
end

function Rpc:start(fn)
  if self.ready then
    callback(fn)
    return
  end
  self.waiting[#self.waiting + 1] = fn
  if self.job then
    return
  end
  self.tail, self.stderr = '', ''
  self.generation = (self.generation or 0) + 1
  local generation = self.generation
  local ok, job = pcall(vim.fn.jobstart, self.opts.cmd, {
    cwd = self.opts.cwd,
    on_stdout = function(_, data)
      if self.generation == generation then
        self:consume(data)
      end
    end,
    on_stderr = function(_, data)
      if self.generation == generation then
        self.stderr = (self.stderr .. table.concat(data, '\n')):sub(-4096)
      end
    end,
    on_exit = function(_, code)
      if self.generation ~= generation then
        return
      end
      self:finish('Codex app-server exited (' .. code .. ')' .. (self.stderr ~= '' and '\n' .. self.stderr or ''))
    end,
  })
  if not ok or job <= 0 then
    self:finish('Unable to start Codex app-server: ' .. tostring(job))
    return
  end
  self.job = job
  self:request('initialize', {
    clientInfo = { name = 'personal_nvim_codex', title = 'Personal Neovim Codex', version = '0.1.0' },
  }, function(err)
    if err then
      local waiting = self.waiting
      self.waiting = {}
      for _, ready in ipairs(waiting) do
        callback(ready, err)
      end
      self:stop()
      return
    end
    self:notify 'initialized'
    self.ready = true
    local waiting = self.waiting
    self.waiting = {}
    for _, ready in ipairs(waiting) do
      callback(ready)
    end
  end)
end

function Rpc:stop()
  if not self.job then
    return
  end
  local job = self.job
  self.generation = (self.generation or 0) + 1
  pcall(vim.fn.jobstop, job)
  self:finish 'Codex app-server stopped'
end

return Rpc
