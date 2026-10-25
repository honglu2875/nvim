-- Uses temporary projects to exercise the real installed language tools.
local temp = vim.fn.tempname()
local function write(name, lines)
  local path = temp .. '/' .. name
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  vim.fn.writefile(lines, path)
  return path
end
local function pass(message)
  print('PASS ' .. message)
end
local function wait(fn, message, timeout)
  assert(vim.wait(timeout or 45000, fn, 100), message)
end
local function run()
  vim.cmd 'doautocmd VimEnter'
  write(
    'python/pyproject.toml',
    { '[project]', 'name = "nvim-smoke"', 'version = "0.0.0"', 'requires-python = ">=3.11"' }
  )
  write('python/main.py', { 'message = "hello"', 'print(message)' })
  write('javascript/tsconfig.json', { '{"compilerOptions":{"strict":true}}' })
  write('javascript/main.ts', { 'const message: string = "hello";', 'console.log(message);' })
  write('go/go.mod', { 'module example.com/nvim-smoke', '', 'go 1.26.0' })
  write('go/main.go', { 'package main', 'func main() {', 'message := "hello"', 'println(message)', '}' })
  write('rust/Cargo.toml', { '[package]', 'name = "nvim-smoke"', 'version = "0.1.0"', 'edition = "2024"' })
  write('rust/src/main.rs', { 'fn main() {', 'let message = "hello";', 'println!("{}", message);', '}' })
  write('lean/lean-toolchain', { 'leanprover/lean4:v4.19.0' })
  write('lean/Main.lean', { 'def message : Nat := 42', '#check message' })
  write('lua/.luarc.json', { '{"runtime":{"version":"LuaJIT"}}' })
  write('lua/main.lua', { 'local message = "hello"', 'print(message)' })
  for _, ext in ipairs { 'c', 'cpp' } do
    write(ext .. '/main.' .. ext, { 'int add(int a, int b) { return a + b; }', 'int main() { return add(1, 2); }' })
    write(ext .. '/compile_commands.json', {
      vim.json.encode {
        {
          directory = temp .. '/' .. ext,
          file = temp .. '/' .. ext .. '/main.' .. ext,
          arguments = { ext == 'c' and 'cc' or 'c++', '-c', temp .. '/' .. ext .. '/main.' .. ext },
        },
      },
    })
  end

  wait(function()
    return require('blink.cmp.fuzzy').implementation_type == 'rust'
  end, 'Blink Rust matcher failed')
  pass 'Blink stable release and Rust matcher'
  require('telescope').load_extension 'fzf'
  require('telescope').load_extension 'ui-select'
  pass 'Telescope native fuzzy matching and UI selection'

  for _, fixture in ipairs {
    { 'lua/main.lua', 'lua_ls', 1, 7, 'lua' },
    { 'python/main.py', 'ty', 1, 7, 'python' },
    { 'javascript/main.ts', 'ts_ls', 1, 13, 'typescript' },
    { 'go/main.go', 'gopls', 3, 10, 'go' },
    { 'rust/src/main.rs', 'rust_analyzer', 1, 6, 'rust' },
    { 'lean/Main.lean', 'leanls', 1, 9 },
    { 'c/main.c', 'clangd', 1, 21, 'c' },
    { 'cpp/main.cpp', 'clangd', 1, 21, 'cpp' },
  } do
    vim.cmd.edit(vim.fn.fnameescape(temp .. '/' .. fixture[1]))
    local buf = vim.api.nvim_get_current_buf()
    local client
    wait(function()
      for _, candidate in ipairs(vim.lsp.get_clients { bufnr = buf }) do
        if candidate.name == fixture[2] and candidate.initialized then
          client = candidate
          return true
        end
      end
    end, fixture[2] .. ' failed to attach')
    local params =
      { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = fixture[3], character = fixture[4] } }
    wait(function()
      local response = client:request_sync('textDocument/hover', params, 5000, buf)
      return response and not response.err and response.result and response.result ~= vim.NIL
    end, fixture[2] .. ' hover failed')
    local completion = client:request_sync('textDocument/completion', params, 10000, buf)
    assert(completion and not completion.err, fixture[2] .. ' completion failed')
    assert(vim.fn.maparg('gd', 'n', false, true).buffer == 1, 'LSP mappings missing')
    if fixture[5] then
      assert(vim.treesitter.get_parser(buf, fixture[5]):parse()[1], fixture[5] .. ' parser failed')
      assert(vim.treesitter.highlighter.active[buf], fixture[5] .. ' highlighting did not start')
    end
    if fixture[2] == 'leanls' then
      assert(vim.fn.maparg('<localleader>i', 'n') ~= '', 'Lean infoview mapping missing')
    end
    pass(fixture[1] .. ': LSP, hover, completion, mappings' .. (fixture[5] and ', highlighting' or ', infoview'))
  end

  vim.cmd.edit(vim.fn.fnameescape(write('python/diagnostics.py', { 'import os', 'value: int = "wrong"' })))
  local buf = vim.api.nvim_get_current_buf()
  ---@type vim.lsp.Client?
  local ruff
  wait(function()
    for _, client in ipairs(vim.lsp.get_clients { bufnr = buf }) do
      if client.name == 'ruff' and client.initialized then
        ruff = client
      end
    end
    local sources = {}
    for _, diagnostic in ipairs(vim.diagnostic.get(buf)) do
      sources[(diagnostic.source or ''):lower()] = true
    end
    return ruff and sources.ruff and sources.ty
  end, 'Expected both Ruff lint and ty type diagnostics')
  assert(ruff, 'Ruff did not attach')
  assert(not ruff.server_capabilities.hoverProvider, 'Ruff must defer hover to ty')
  local actions = ruff:request_sync('textDocument/codeAction', {
    textDocument = { uri = vim.uri_from_bufnr(buf) },
    range = { start = { line = 0, character = 0 }, ['end'] = { line = 1, character = 0 } },
    context = { diagnostics = {}, only = { 'source.fixAll.ruff' } },
  }, 10000, buf)
  assert(actions and not actions.err and actions.result and #actions.result > 0, 'Ruff fix action missing')
  local action = actions.result[1]
  if not action.edit then
    local resolved = ruff:request_sync('codeAction/resolve', action, 10000, buf)
    assert(resolved and not resolved.err, 'Ruff code action did not resolve')
    action = resolved.result
  end
  assert(action.edit, 'Ruff fix has no workspace edit')
  vim.lsp.util.apply_workspace_edit(action.edit, ruff.offset_encoding)
  assert(
    not table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('import os', 1, true),
    'Ruff unused-import fix failed'
  )
  vim.cmd 'write'
  pass 'ty type diagnostics, Ruff lint diagnostics, and applying Ruff fixes'

  for _, fixture in ipairs {
    { 'python/format.py', { 'value= 1' } },
    { 'javascript/format.ts', { 'const value={a:1,b:2}' } },
    { 'lua/format.lua', { 'local value={a=1,b=2}', 'print(value)' } },
    { 'go/format.go', { 'package main', 'func example(){println("ok")}' } },
    { 'rust/src/format.rs', { 'fn main(){println!("ok");}' } },
    { 'cpp/format.cpp', { 'int main(){return 0;}' } },
  } do
    vim.cmd.edit(vim.fn.fnameescape(write(fixture[1], fixture[2])))
    local before = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local format_error
    require('conform').format({ async = false, timeout_ms = 10000, lsp_format = 'never' }, function(err)
      format_error = err
    end)
    assert(not format_error, vim.inspect(format_error))
    assert(
      not vim.deep_equal(before, vim.api.nvim_buf_get_lines(0, 0, -1, false)),
      'Formatting did not change ' .. fixture[1]
    )
    vim.cmd 'write'
    pass('formatting ' .. fixture[1])
  end

  vim.cmd 'enew'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'start here', 'the unique needle is here', 'end here' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_feedkeys('a', 't', false)
  require('flash').jump {
    pattern = 'needle',
    labels = 'a',
    search = { multi_window = false },
    jump = { autojump = true },
  }
  assert(vim.api.nvim_win_get_cursor(0)[1] == 2, 'Flash did not jump to the target')
  pass 'Flash jumps to a visible search match'
  vim.bo.modified = false
  assert(vim.g.colors_name == 'retrobox', 'Expected Retrobox')
  assert(vim.fn.exists ':Codex' == 2, 'Custom Codex plugin missing')
  local config = require('lazy.core.config').plugins
  assert(not config['friendly-snippets'] and not config['LuaSnip'], 'Snippet packages should be deferred')
  assert(config['copilot.vim'], 'Copilot missing')
  pass 'theme, custom Codex commands, Copilot, and deferred snippets'
end
local ok, err = xpcall(run, debug.traceback)
local clients = vim.lsp.get_clients()
for _, client in ipairs(clients) do
  client:stop()
end
vim.wait(10000, function()
  for _, client in ipairs(clients) do
    if not client:is_stopped() then
      return false
    end
  end
  return true
end, 100)
if not ok then
  io.stderr:write(err .. '\nFixtures: ' .. temp .. '\n')
else
  vim.fn.delete(temp, 'rf')
end
vim.cmd(ok and 'qa!' or 'cquit 1')
