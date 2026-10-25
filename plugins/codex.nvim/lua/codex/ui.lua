local M = { views = {} }

local function valid(win)
  return win and vim.api.nvim_win_is_valid(win)
end
local function buffer(name, editable)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].modifiable = editable
  return buf
end

function M.get(session)
  if not M.views[session.root] then
    local key = vim.fn.sha256(session.root):sub(1, 12)
    M.views[session.root] = {
      log = buffer('codex://' .. key .. '/chat', false),
      input = buffer('codex://' .. key .. '/prompt', true),
    }
  end
  return M.views[session.root]
end

function M.is_panel(buf)
  return M.root(buf) ~= nil
end

function M.root(buf)
  for root, view in pairs(M.views) do
    if view.log == buf or view.input == buf then
      return root
    end
  end
end

function M.visible(session)
  local view = M.views[session.root]
  return view and (valid(view.log_win) or valid(view.input_win))
end

function M.hide(session)
  local view = M.views[session.root]
  if not view then
    return
  end
  for _, win in ipairs { view.input_win or -1, view.log_win or -1 } do
    if valid(win) then
      pcall(vim.api.nvim_win_close, win, false)
    end
  end
  view.input_win, view.log_win = nil, nil
end

function M.render(session)
  local view = M.get(session)
  local lines = { '# Codex', '', session.root, '', 'Status: ' .. (session.status or 'ready'), '' }
  for _, message in ipairs(session.messages) do
    lines[#lines + 1] = '## ' .. message.role
    lines[#lines + 1] = ''
    vim.list_extend(lines, vim.split(message.text or '', '\n', { plain = true }))
    lines[#lines + 1] = ''
  end
  local at_end = not valid(view.log_win)
    or vim.api.nvim_win_get_cursor(view.log_win)[1] >= vim.api.nvim_buf_line_count(view.log) - 2
  vim.bo[view.log].modifiable = true
  vim.api.nvim_buf_set_lines(view.log, 0, -1, false, lines)
  vim.bo[view.log].modifiable = false
  if valid(view.log_win) and at_end then
    vim.api.nvim_win_set_cursor(view.log_win, { #lines, 0 })
  end
end

function M.update(session)
  if session.render_pending then
    return
  end
  session.render_pending = true
  vim.defer_fn(function()
    session.render_pending = nil
    if not session.closed then
      M.render(session)
    end
  end, 40)
end

function M.open(session, opts, actions)
  local view = M.get(session)
  if valid(view.input_win) and valid(view.log_win) then
    vim.api.nvim_set_current_win(view.input_win)
    return view
  end
  M.hide(session)
  vim.cmd('botright ' .. math.max(32, math.floor(vim.o.columns * opts.width)) .. 'vsplit')
  view.log_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(view.log_win, view.log)
  vim.cmd('belowright ' .. opts.input_height .. 'split')
  view.input_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(view.input_win, view.input)
  for _, win in ipairs { view.log_win, view.input_win } do
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].wrap = true
    vim.wo[win].signcolumn = 'no'
    vim.wo[win].winfixwidth = true
    vim.wo[win].spell = false
  end
  vim.wo[view.input_win].winbar = ' Prompt: Ctrl-S send · Ctrl-C cancel · q hide'
  for _, buf in ipairs { view.log, view.input } do
    vim.keymap.set('n', 'q', function()
      M.hide(session)
    end, { buffer = buf, desc = 'Hide Codex' })
    vim.keymap.set({ 'n', 'i' }, '<C-c>', actions.cancel, { buffer = buf, desc = 'Cancel Codex turn' })
  end
  vim.keymap.set({ 'n', 'i' }, '<C-s>', actions.send, { buffer = view.input, desc = 'Send to Codex' })
  vim.keymap.set('n', '<CR>', actions.send, { buffer = view.input, desc = 'Send to Codex' })
  M.render(session)
  return view
end

function M.draft(session)
  return table.concat(vim.api.nvim_buf_get_lines(M.get(session).input, 0, -1, false), '\n')
end

function M.set_draft(session, text)
  vim.api.nvim_buf_set_lines(M.get(session).input, 0, -1, false, vim.split(text, '\n', { plain = true }))
end

function M.review(title, text, done)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'markdown'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, '\n', { plain = true }))
  vim.bo[buf].modifiable = false
  local width = math.max(20, math.min(100, vim.o.columns - 4))
  local height = math.max(3, math.min(30, vim.o.lines - 6))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = 1,
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    title = title,
  })
  vim.wo[win].wrap = true
  for _, key in ipairs { 'q', '<Esc>' } do
    vim.keymap.set('n', key, function()
      vim.api.nvim_win_close(win, true)
    end, { buffer = buf })
  end
  if done then
    vim.api.nvim_create_autocmd('BufWipeout', {
      buffer = buf,
      once = true,
      callback = function()
        vim.schedule(done)
      end,
    })
  end
end

return M
