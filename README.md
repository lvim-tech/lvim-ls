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
  state.lua          shared module state — replaces all _G.* globals
  data.lua           missing-tool reporting for the unified installer prompt
  config/            data-only defaults (lsp / features / progress / message)
  core/
    bootstrap.lua    one-time engine setup
    manager.lua      LSP client lifecycle (start / attach / detach / enable)
    project.lua      project-root resolution and per-root server sets
    schema.lua       server/tool requirement schema
    features.lua     per-filetype feature resolution
    progress.lua     $/progress aggregation (data only)
    dap.lua          debug-adapter requirements
    globals.lua      runtime globals/env wiring
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

### LVIM IDE

Pulled in automatically as a dependency of `lvim-lsp`:

```lua
modules["lvim-tech/lvim-lsp"] = {
    dependencies = { "lvim-tech/lvim-ls", "lvim-tech/lvim-utils" },
    opts = { ... }, -- engine + UI options, configured through lvim-lsp
}
```

### lazy.nvim

```lua
return {
    "lvim-tech/lvim-ls",
    dependencies = { "lvim-tech/lvim-pkg" },
    -- no config(): a library, configured through lvim-lsp
}
```

### Native (vim.pack / packadd)

```lua
-- In your init.lua, after the plugin is on the runtimepath. No setup() — the
-- engine is driven by lvim-lsp; require its modules directly when embedding it.
vim.pack.add({
    { src = "https://github.com/lvim-tech/lvim-pkg" },
    { src = "https://github.com/lvim-tech/lvim-ls" },
})
```

### packer.nvim

```lua
use({
    "lvim-tech/lvim-ls",
    requires = { "lvim-tech/lvim-pkg" },
    -- no config: a library, configured through lvim-lsp
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

-- Per-project overrides under .lvim-ls/ (show / reset, used by the UI):
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
