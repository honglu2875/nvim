-- Language servers run directly; this configuration uses no remote-plugin hosts.
for _, host in ipairs { 'node', 'perl', 'ruby', 'python3' } do
  vim.g['loaded_' .. host .. '_provider'] = 0
end

local opt = vim.opt
opt.number = true
opt.mouse = 'a'
opt.tabstop = 4
opt.softtabstop = 4
opt.shiftwidth = 4
opt.expandtab = true
opt.title = true
opt.showmode = false
opt.breakindent = true
opt.undofile = true
opt.ignorecase = true
opt.smartcase = true
opt.signcolumn = 'yes'
opt.updatetime = 250
opt.timeoutlen = 300
opt.splitright = true
opt.splitbelow = true
opt.list = true
opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }
opt.inccommand = 'split'
opt.cursorline = true
opt.scrolloff = 10
opt.termguicolors = true
opt.confirm = true
opt.autoread = true

vim.schedule(function()
  opt.clipboard = 'unnamedplus'
end)
vim.cmd.colorscheme 'retrobox'
vim.cmd 'highlight Comment gui=NONE'
vim.g.netrw_banner = 0
vim.g.netrw_liststyle = 3
vim.filetype.add { extension = { gotmpl = 'gotmpl' } }
