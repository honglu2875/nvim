local M = {}

function M.root(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local path = name ~= '' and name or vim.fn.getcwd()
  local root = vim.fs.root(
    path,
    { '.git', 'pyproject.toml', 'package.json', 'go.mod', 'Cargo.toml', 'lakefile.lean', 'lakefile.toml' }
  ) or (name ~= '' and vim.fs.dirname(name) or vim.fn.getcwd())
  return vim.uv.fs_realpath(root) or vim.fs.normalize(root)
end

function M.capture(buf, first, last, max_bytes)
  assert(vim.bo[buf].buftype == '', 'Select a source-file buffer to attach context')
  local count = vim.api.nvim_buf_line_count(buf)
  first, last = math.max(1, first or 1), math.min(count, last or count)
  local lines = vim.api.nvim_buf_get_lines(buf, first - 1, last, false)
  local text = table.concat(lines, '\n')
  assert(#text <= max_bytes, 'Context exceeds ' .. max_bytes .. ' bytes; select a smaller range')
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' then
    name = '[unsaved buffer]'
  end
  -- Pick a fence that cannot be closed by the attached source text.
  local fence = '```'
  while text:find(fence, 1, true) do
    fence = fence .. '`'
  end
  return ('File: %s\nLines: %d-%d%s\n%s%s\n%s\n%s'):format(
    name,
    first,
    last,
    vim.bo[buf].modified and ' (unsaved buffer contents)' or '',
    fence,
    vim.bo[buf].filetype,
    text,
    fence
  )
end

return M
