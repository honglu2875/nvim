local M = {}
function M.check()
  vim.health.start 'Personal Codex client'
  if vim.fn.executable 'codex' == 1 then
    local result = vim.system({ 'codex', '--version' }, { text = true }):wait(5000)
    if result.code == 0 then
      vim.health.ok(vim.trim(result.stdout))
    else
      vim.health.error('codex --version failed', { result.stderr })
    end
  else
    vim.health.error 'Codex CLI is not installed or is missing from PATH'
  end
  vim.health.info 'Uses local app-server stdio and the existing Codex login/configuration.'
  vim.health.info 'Protocol baseline: Codex CLI 0.164.0. Run the plugin tests after CLI upgrades.'
end
return M
