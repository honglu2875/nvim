# Personal Codex client for Neovim

A native Neovim chat interface to the installed `codex app-server`. All source
is owned and maintained in this configuration repository. No terminal emulator
or third-party Codex plugin is involved.

## Use

Sign in using the normal Codex CLI if needed (`codex login`). The client reuses
that installation's authentication, model and policy configuration. Open with
`:Codex` or `<leader>aa`; type in the lower prompt pane and press Ctrl-S to send.
Normal-mode Enter also sends. Insert-mode Enter inserts a newline.

- `:CodexAsk {text}` drafts a prompt for review without submitting it.
- `:CodexContext` appends the current buffer to the draft, including unsaved text.
  A visual selection or `:2,8CodexContext` attaches just those lines. Context is
  limited to 100 KiB by default; use a narrower selection for large files.
- `:CodexSend` submits the draft. Sending another prompt during an active turn
  is rejected; use `:CodexCancel` or Ctrl-C in the panel to interrupt first.
- `q` in Normal mode hides the panel. The conversation continues in the background.
- `:CodexNew` starts a fresh conversation in the current project.
- `:CodexResume [thread-id]` resumes the most recently saved project thread,
  or a supplied id. Recent history is restored from app-server's response.
- `:CodexReview` displays the latest reported patch in a scrollable buffer.
- `:CodexStop` stops the local app-server. Use `:CodexResume` to reconnect to a
  previously saved conversation.
- `:checkhealth codex` checks the executable and shows the protocol baseline.

Each project gets its own draft, transcript, and thread. The root is the nearest
Git root or recognized language project marker. Switching to an existing panel
routes commands to that panel's project. Source buffers modified on disk are
checked after a turn; Neovim's normal modified-buffer protections remain active.

## Approvals and user input

The plugin responds to command/file approvals, additional permission requests,
and structured user questions. Approval dialogs offer a full detail view before
allowing an operation. File-change requests include the reported patch when
available. Escape cancels an approval; it never selects an affirmative default.
Concurrent requests queue, and responses to already-resolved requests are ignored.

Permission settings are inherited from Codex rather than replaced with automatic
approval flags. If existing Codex policy allows an operation without a prompt,
the plugin does not manufacture a second prompt.

This initial version does not render MCP elicitation forms or URL login flows;
it explicitly declines those requests. Unknown client-side RPC methods receive
a protocol error instead of silently hanging. It does not register dynamic tools
or implement client-managed authentication tokens.

## Configuration

Edit `lua/plugins/codex.lua`. The plugin's defaults are:

```lua
require('codex').setup {
  cmd = { 'codex', 'app-server', '--listen', 'stdio://' },
  width = 0.45,
  input_height = 7,
  max_context_bytes = 100 * 1024,
  timeout_ms = 30000,
  thread = {},
}
```

`thread` accepts supported `thread/start` options, for example a preferred model.
The current project's working directory is always supplied by the plugin.
Omitted options follow Codex configuration. The command is an argument list,
never a shell command string.

Only project paths and thread ids are saved by this plugin, under
`stdpath('state')/codex/`. Codex itself manages conversation persistence. Those
state files have owner-only permissions. Set `state_dir = false` to disable
the plugin's saved-thread index.

## Code map

| File | Responsibility |
| --- | --- |
| `lua/codex/rpc.lua` | Child process, JSONL framing, handshake, request ids, timeouts and disconnects |
| `lua/codex/init.lua` | Project sessions, thread/turn lifecycle, streamed messages and commands |
| `lua/codex/ui.lua` | Native transcript, editable prompt and patch/details windows |
| `lua/codex/context.lua` | Project discovery and explicit buffer/selection capture |
| `lua/codex/requests.lua` | Approval queue and user questions |
| `lua/codex/health.lua` | Executable health check |

Changes to rendering, keybindings, prompt construction, and session behavior can
be made independently. A model picker, conversation browser, richer diff review,
and active-turn steering can be added without replacing the transport.

## Validation and protocol updates

Protocol baseline: **Codex CLI 0.164.0**. The app-server interface is evolving;
after updating the CLI, regenerate its schemas and run these tests:

```sh
codex app-server generate-json-schema --out /tmp/codex-protocol
nvim --headless -u NONE -l plugins/codex.nvim/tests/run.lua
```

The deterministic peer tests split JSON across chunks, include Unicode, deliver
completion before a request response, simulate server failures, exercise project
routing, and verify approval/cancellation behavior. They never call a model.

An optional live test sends one short prompt using the current Codex account and
creates an ephemeral, read-only thread:

```sh
CODEX_NVIM_LIVE=1 nvim --headless -u NONE -l plugins/codex.nvim/tests/live.lua
```

The protocol was checked against generated schemas from the installed CLI and
[official app-server documentation](https://learn.chatgpt.com/docs/app-server).
