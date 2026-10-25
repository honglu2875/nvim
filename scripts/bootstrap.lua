-- Run with this configuration loaded: nvim --headless '+luafile scripts/bootstrap.lua'
local function run()
  local registry = require 'mason-registry'
  local refreshed, refresh_ok = false, false
  registry.refresh(function(ok)
    refreshed, refresh_ok = true, ok
  end)
  assert(
    vim.wait(60000, function()
      return refreshed
    end, 100),
    'Mason registry refresh timed out'
  )
  assert(refresh_ok, 'Mason registry refresh failed')
  local packages = require('config.tools').packages
  for _, name in ipairs(packages) do
    assert(registry.has_package(name), 'Mason package not found: ' .. name)
    local pkg = registry.get_package(name)
    if not pkg:is_installed() and not pkg:is_installing() then
      pkg:install()
    end
  end
  local complete = vim.wait(300000, function()
    for _, name in ipairs(packages) do
      local pkg = registry.get_package(name)
      if pkg:is_installing() then
        return false
      end
    end
    return true
  end, 200)
  assert(complete, 'Mason installation timed out; inspect :MasonLog')
  for _, name in ipairs(packages) do
    assert(registry.get_package(name):is_installed(), name .. ' installation failed; inspect :MasonLog')
    print('Installed ' .. name)
  end
  require('nvim-treesitter').install(require('config.tools').parsers):wait(300000)
  for _, lang in ipairs(require('config.tools').parsers) do
    local ok, loaded = pcall(vim.treesitter.language.add, lang)
    assert(ok and loaded, 'Missing parser: ' .. lang)
  end
  print 'Configured tools and parsers are installed'
end
local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. '\n')
end
vim.cmd(ok and 'qa!' or 'cquit 1')
