# Personal Neovim

A small, independent Lua configuration, with a locally owned Codex app-server
client in `plugins/codex.nvim`. Kickstart informed the basic editor settings;
this repository has no dependency on its configuration or Git history.

## Try this build

```sh
NVIM_APPNAME=nvim-next nvim
```

The app name isolates configuration, plugins, Mason packages, cache, and state.
The previous setup remains available with ordinary `nvim` while this build is
being tried. A complete snapshot of that setup is stored separately under
`~/.local/state/nvim-maintenance/`.

## Installation

Requires Neovim 0.12+, Git, curl, tar/unzip, a C compiler, make, Node/npm, and
Python with venv support. Telescope uses ripgrep and optionally fd. Go and Rust
development require their toolchains; Lean uses Elan and each project's
`lean-toolchain`. A Nerd Font is assumed; disable `have_nerd_font` in `init.lua`
if needed. Clipboard integration uses the host's clipboard utility.

Clone this repository to your chosen Neovim configuration directory. For an
isolated installation named `nvim-next`, start it with the command above, then:

```vim
:Lazy sync
:MasonToolsInstall
:ParsersInstall
```

Wait for each installation step to finish. Mason provides the Tree-sitter CLI
as well as editor tools. The parser step requires it to be installed first.
For a scripted installation from the repository directory:

```sh
NVIM_APPNAME=nvim-next nvim --headless '+Lazy! restore' +qa
NVIM_APPNAME=nvim-next nvim --headless '+luafile scripts/bootstrap.lua'
```

`lazy-lock.json` pins plugins. `lua/config/tools.lua` is the tool/parser manifest;
Mason's downloaded tool versions are separate from Lazy's plugin lockfile.

## Components

| Purpose | Choice |
| --- | --- |
| Plugin management | lazy.nvim |
| Language client | Native `vim.lsp` + nvim-lspconfig |
| Tool installation | Mason, mason-lspconfig, mason-tool-installer |
| Python | ty language server; Ruff diagnostics, fixes and formatting |
| JavaScript / TypeScript | typescript-language-server; Prettier |
| Go | gopls; gofmt |
| Rust | rust-analyzer; rustfmt |
| Lean | lean.nvim with the project-selected Lean server |
| Lua | LuaLS + lazydev; StyLua |
| C / C++ | clangd; clang-format |
| Completion | Blink stable 1.x; LSP, path, buffer and lazydev sources |
| Highlighting | Native Tree-sitter; nvim-treesitter parsers and queries; Lean semantic highlighting |
| Search | Telescope + native fzf + UI selection |
| Files | Built-in netrw |
| Git | Gitsigns |
| Screen jumps | Flash |
| Editor conveniences | vim-sleuth, mini.ai, mini.surround, mini.statusline, which-key |
| Theme | Built-in Retrobox |
| AI | Existing copilot.vim; independently owned native Codex panel |

Python uses one semantic server, ty. Ruff supplies lint diagnostics and code
actions; its hover is disabled to avoid duplicate hover providers. Project
configuration controls lint and type-checking rules. Fixes are explicit code
actions; saving formats code without automatically applying every lint fix.

Formatting runs on save except C/C++, where it remains manual. Project formatter
configuration is respected. For C/C++, supply `compile_commands.json` from the
build system so clangd knows include paths and compiler flags.

Snippet packs and additional snippet engines are deferred. Ordinary LSP
completion can still use Neovim's built-in snippet expansion. A later choice
can compare native snippets, mini.snippets and LuaSnip without changing LSP.

## Everyday keys

Leader and local leader are Space. Built-in Neovim mappings such as `K`, `grn`,
`gra`, `[d`, `]d`, and `gc` remain available.

| Keys | Action |
| --- | --- |
| `<leader>j` | Flash: type a search, then a displayed label |
| `<leader>J` | Flash syntax-node selection |
| `<leader>sf`, `<leader>sg` | Find files, search project text |
| `<leader><space>`, `<leader>/` | Buffers, search current buffer |
| `<leader>fe` | Built-in file browser |
| `gd`, `grr`, `gI`, `<leader>D` | Definitions, references, implementations, type definition |
| `<leader>rn`, `<leader>ca` | Rename, code actions (including Ruff fixes) |
| `<leader>e`, `<leader>q` | Diagnostic details, diagnostic list |
| `<leader>f`, `<leader>tf` | Format, toggle buffer's format-on-save |
| `[c`, `]c` | Previous/next Git hunk |
| `<leader>hs`, `<leader>hr`, `<leader>hp` | Stage/unstage, reset, preview hunk |
| `<leader>hb`, `<leader>tb` | Blame line, toggle persistent blame |
| `<leader>i` in Lean | Toggle infoview |
| `<leader>aa` | Toggle Codex panel |
| `<leader>ac` | Attach buffer or selected lines to the Codex draft |
| `<leader>ax`, `<leader>an`, `<leader>ar` | Cancel, new conversation, resume last project conversation |
| `<leader>ad` | Review Codex's reported changes |

Blink uses Ctrl-Y to accept, Ctrl-N/P to select, Ctrl-Space to open, and Ctrl-E
to dismiss. Tab remains available to the existing Copilot mapping. Flash leaves
`s`, `f`, `t`, `/`, and `?` unchanged.

## Customizing

- `lua/config/`: editor settings, keys and the language-tool manifest.
- `lua/plugins/`: one small spec per feature.
- `lua/plugins/codex.lua`: your Codex plugin settings and keybindings.
- `plugins/codex.nvim/`: all source, documentation and tests for your own plugin.

See [the Codex plugin README](plugins/codex.nvim/README.md) for its architecture
and customization points. The plugin is ordinary tracked source, not a Git
submodule, remote plugin dependency, or downloaded wrapper.

## Maintenance and checks

Use `:Lazy update` deliberately, review the lockfile, and commit working updates.
Use `:MasonToolsUpdate` for language tools and `:TSUpdate` for parsers. Mason
updates are not triggered automatically on every startup.

```sh
# Offline tests for the custom Codex client; no account/model access.
nvim --headless -u NONE -l plugins/codex.nvim/tests/run.lua

# Real installed LSPs, formatters, parsers and Flash, in temporary projects.
NVIM_APPNAME=nvim-next nvim --headless '+luafile scripts/smoke.lua'
NVIM_APPNAME=nvim-next nvim --headless '+luafile scripts/git-smoke.lua'

# Full health report in the editor.
NVIM_APPNAME=nvim-next nvim '+checkhealth'
```

The integration fixture currently uses Go 1.26+ and Lean 4.19.0. The latter is
deliberate: it checks that an older project's Lean toolchain is respected.

The independent Git repository is ready for a private GitHub remote after the
configuration and first plugin version have been tried. Runtime downloads,
Codex account data, transcripts and backups do not belong in the repository.

## Acknowledgment

Basic editor settings and familiar mappings were adapted from
[kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim). Its MIT notice is
preserved in `LICENSE.kickstart`. Other plugins retain their upstream licenses;
their checkouts live outside this repository.
