-- Server requests are queued so concurrent approvals cannot overwrite each other.
local M = { queue = {}, pending = {} }
local ui = require 'codex.ui'
local function key(id)
  return vim.json.encode(id)
end

function M.clear()
  for _, request in pairs(M.pending) do
    request.alive = false
  end
  M.queue, M.pending, M.active = {}, {}, nil
end

function M.resolved(id)
  local request = M.pending[key(id)]
  if not request then
    return
  end
  request.alive = false
  M.pending[key(id)] = nil
  if M.active == request then
    M.active = nil
    vim.schedule(M.next)
  end
end

function M.cancel_turn(thread, turn)
  local ids = {}
  for _, request in pairs(M.pending) do
    local p = request.message.params
    if p.threadId == thread and p.turnId == turn then
      ids[#ids + 1] = request.message.id
    end
  end
  for _, id in ipairs(ids) do
    M.resolved(id)
  end
end

local function finish(request, result, err)
  if not request.alive then
    return
  end
  request.rpc:reply(request.message.id, result, err)
  M.resolved(request.message.id)
end

local function choose(request, title, options, handler)
  if not request.alive then
    return
  end
  vim.ui.select(options, { prompt = title }, function(choice)
    if request.alive then
      handler(choice)
    end
  end)
end

local function approval(request)
  local p, method = request.message.params, request.message.method
  local details = vim.inspect(p)
  if request.details then
    details = details .. '\n\n' .. request.details
  end
  local label = type(p.command) == 'string' and p.command
    or type(p.reason) == 'string' and p.reason
    or 'permission request'
  local prompt = type(p.networkApprovalContext) == 'table'
      and ('Codex network: ' .. (p.networkApprovalContext.host or 'requested host'))
    or (method == 'item/fileChange/requestApproval' and 'Codex file changes')
    or 'Codex command: ' .. label:sub(1, 100)
  local decisions = { ['Decline'] = 'decline', ['Allow once'] = 'accept', ['Cancel turn'] = 'cancel' }
  local choices = { 'Review details', 'Decline', 'Allow once', 'Cancel turn' }
  -- Honor servers which restrict the available decision set.
  if type(p.availableDecisions) == 'table' then
    choices = { 'Review details' }
    for _, label in ipairs { 'Decline', 'Allow once', 'Cancel turn' } do
      if vim.tbl_contains(p.availableDecisions, decisions[label]) then
        choices[#choices + 1] = label
      end
    end
  end
  local show
  show = function()
    choose(request, prompt, choices, function(choice)
      if choice == 'Review details' then
        ui.review('Codex approval · q to return', details, show)
      else
        finish(request, { decision = decisions[choice] or 'cancel' })
      end
    end)
  end
  show()
end

local function questions(request)
  local answers, list = vim.empty_dict(), request.message.params.questions or {}
  local function ask(index)
    if not request.alive then
      return
    end
    local question = list[index]
    if not question then
      finish(request, { answers = answers })
      return
    end
    local function answer(value)
      if not request.alive then
        return
      end
      -- Esc means no answer, never the preselected recommendation.
      answers[question.id] = { answers = value and { value } or {} }
      ask(index + 1)
    end
    if question.isSecret then
      local ok, value = pcall(vim.fn.inputsecret, question.question .. ': ')
      answer(ok and value or nil)
    elseif type(question.options) == 'table' and #question.options > 0 then
      local options = {}
      for _, option in ipairs(question.options) do
        options[#options + 1] = { label = option.label, description = option.description }
      end
      options[#options + 1] = { label = 'Write an answer…', custom = true }
      vim.ui.select(options, {
        prompt = question.question,
        format_item = function(option)
          return option.label .. (option.description and ' — ' .. option.description or '')
        end,
      }, function(option)
        if not request.alive then
          return
        end
        if option and option.custom then
          vim.ui.input({ prompt = question.question .. ': ' }, answer)
        else
          answer(option and option.label)
        end
      end)
    else
      vim.ui.input({ prompt = question.question .. ': ' }, answer)
    end
  end
  ask(1)
end

function M.next()
  if M.active then
    return
  end
  local request = table.remove(M.queue, 1)
  if not request then
    return
  end
  if not request.alive then
    M.next()
    return
  end
  M.active = request
  local method = request.message.method
  if method == 'item/commandExecution/requestApproval' or method == 'item/fileChange/requestApproval' then
    approval(request)
  elseif method == 'item/tool/requestUserInput' then
    questions(request)
  elseif method == 'item/permissions/requestApproval' then
    local show
    show = function()
      choose(
        request,
        'Codex additional permissions',
        { 'Review details', 'Decline', 'Allow requested permissions for this turn' },
        function(choice)
          if choice == 'Review details' then
            ui.review('Requested permissions · q to return', vim.inspect(request.message.params), show)
          else
            finish(request, {
              permissions = choice == 'Allow requested permissions for this turn'
                  and request.message.params.permissions
                or vim.empty_dict(),
              scope = 'turn',
            })
          end
        end
      )
    end
    show()
  elseif method == 'mcpServer/elicitation/request' then
    -- Structured MCP forms need their own renderer. Never fabricate answers.
    vim.notify('Codex: MCP elicitation is not implemented in this version; request declined', vim.log.levels.WARN)
    finish(request, { action = 'decline', content = vim.NIL })
  else
    finish(request, nil, { code = -32601, message = 'Unsupported Neovim client request: ' .. method })
  end
end

function M.handle(message, rpc, details)
  local request = { message = message, rpc = rpc, details = details, alive = true }
  M.pending[key(message.id)] = request
  M.queue[#M.queue + 1] = request
  M.next()
end

return M
