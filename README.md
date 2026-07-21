# lvim-ls

The **engine** of the LVIM language-server stack: all LSP lifecycle, project
resolution, feature/dependency data and progress tracking — with **no UI**. The
visual layer (panels, forms, highlights, notifications) lives in
[lvim-lsp](https://github.com/lvim-tech/lvim-lsp), which drives this engine.

This split keeps the heavy, stateful logic isolated and composable: `lvim-ls`
answers "what servers/tools does this filetype need, what is running, what is
missing", while `lvim-lsp` decides how to show it and `lvim-pkg` /
`lvim-installer` decide how to install it.

[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](https://github.com/lvim-tech/lvim-ls/blob/main/LICENSE)

## Architecture

```
lvim-ls/
  state.lua          shared runtime state — replaces all _G.* globals
  config/            the live config: lsp / features / progress / message defaults
  data.lua           missing-tool reporting for the unified installer prompt
  health.lua         :checkhealth lvim-ls
  core/
    bootstrap.lua    one-time engine setup (autocmds + initial sweep)
    manager.lua      LSP client lifecycle (start / attach / detach / enable)
    project.lua      project-root resolution and per-project overrides
    schema.lua       per-server settings-form schema resolver (get/set/resolve/apply)
    features.lua     per-buffer LSP feature setup (diagnostics / codelens / on_attach)
    progress.lua     $/progress aggregation (data only)
    dap.lua          registers DAP adapters + configurations from server configs
    globals.lua      JSON persistence of interactively-toggled feature flags
  utils/             notify / debug / levels helpers
```

No global namespace is touched: every module reads and writes through
`lvim-ls.state`, so the engine stays side-effect free and testable.

## Installation

`lvim-ls` is the engine behind [lvim-lsp](https://github.com/lvim-tech/lvim-lsp)
and is normally installed as its dependency — you do not configure it directly.

`lvim-ls` is a LIBRARY — it has no `setup()` of its own; it is configured through
`lvim-lsp`. The methods below install the engine (and its dependencies); the
options are passed via `lvim-lsp.setup`.

Requires Neovim >= 0.10.

### lvim-installer (recommended)

Install and manage it from the LVIM package manager — open the **Plugins** tab and
install / update / pin it:

```vim
:LvimInstaller plugins
```

lvim-installer installs plugins through Neovim's built-in `vim.pack`, so no external
plugin manager is needed. `lvim-ls` is pulled in automatically as a dependency of
`lvim-lsp`.

### lazy.nvim

```lua
return {
    "lvim-tech/lvim-ls",
    dependencies = { "lvim-tech/lvim-pkg" },
    -- no config(): a library, configured through lvim-lsp
}
```

### packer.nvim

```lua
use({
    "lvim-tech/lvim-ls",
    requires = { "lvim-tech/lvim-pkg" },
    -- no config: a library, configured through lvim-lsp
})
```

### Native (vim.pack)

```lua
-- In your init.lua, after the plugin is on the runtimepath. No setup() — the
-- engine is driven by lvim-lsp; require its modules directly when embedding it.
vim.pack.add({
    { src = "https://github.com/lvim-tech/lvim-pkg" },
    { src = "https://github.com/lvim-tech/lvim-ls" },
})
```

## Usage

`lvim-ls` is a library, not a standalone plugin — there is no `setup()` here.
It is required and configured through `lvim-lsp`:

```lua
require("lvim-lsp").setup({
    -- engine (data) options are merged into lvim-ls.config; UI options stay in lvim-lsp
})
```

Consumers require the engine modules directly, e.g.:

```lua
local manager = require("lvim-ls.core.manager")
local servers = manager.get_compatible_lsp_for_ft("go")
local missing = manager.missing_tools_for_server("gopls")
manager.restart_server("gopls") -- stop all instances and re-attach served buffers

-- Per-project overrides under .lvim/ls/ (show / reset, used by the UI):
local project = require("lvim-ls.core.project")
local overrides = project.list_overrides(vim.uv.cwd()) -- servers / filetypes / efm_tools
project.clear_server(vim.uv.cwd(), "gopls")
```

## Installer integration

`lvim-ls.data` exposes the missing-tool surface consumed by `lvim-pkg`'s
provider registry, so [lvim-installer](https://github.com/lvim-tech/lvim-installer)
can offer the missing Mason tools for a filetype alongside treesitter parsers,
without `lvim-ls` knowing anything about installation or UI:

```lua
local data = require("lvim-ls.data")
data.missing_for_ft("go") -- server_name -> { missing dependency names }
data.items_for_ft("go") -- flat LvimPkgItem list for the installer prompt
```

## Part of the LVIM ecosystem

- [lvim-lsp](https://github.com/lvim-tech/lvim-lsp) — the UI for this engine
- [lvim-pkg](https://github.com/lvim-tech/lvim-pkg) — package/tool manager
- [lvim-installer](https://github.com/lvim-tech/lvim-installer) — install UI
- [lvim-ts](https://github.com/lvim-tech/lvim-ts) — treesitter runtime
- [lvim-utils](https://github.com/lvim-tech/lvim-utils) — shared UI/notify helpers
