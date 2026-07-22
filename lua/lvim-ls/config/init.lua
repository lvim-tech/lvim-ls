-- lvim-ls: the LIVE engine configuration (the canonical config module).
--
-- This module returns the single, mutable config table for the whole plugin. It is built
-- once by deep-merging the DATA sections (lsp/features/progress/message); UI config
-- (info/menus/project/highlights/form) is not defined here — lvim-lsp injects it into this
-- SAME table at setup. `state.configure()` merges user options into this table IN PLACE (via
-- lvim-utils.utils.merge — clean array replace), so every `require("lvim-ls.config")` reader
-- sees the effective, post-setup values. `lvim-ls.state.config` is a back-compat re-export of
-- this exact table.
--
---@module "lvim-ls.config"

---@class LvimLspNotifyConfig
---@field enabled   boolean          Set to false to silence all notifications (default: true)
---@field min_level integer          Minimum vim.log.levels.* to display (default: INFO)
---@field title     string           Notification popup title (default: "Lvim LSP")

---@class LvimLspDebugConfig
---@field enabled   boolean          Set to true to enable file-based debug logging (default: false)
---@field min_level integer          Minimum level to record (default: DEBUG)

---@class LvimLspInfoIconsConfig
---@field server  string|nil
---@field section string|nil
---@field item    string|nil
---@field check   string|nil
---@field mason   string|nil
---@field fold    string|nil
---@field error   string|nil
---@field warn    string|nil
---@field info    string|nil
---@field hint    string|nil

---@class LvimLspInfoConfig
---@field popup_title string                    Title shown at the top of the info window
---@field icons       LvimLspInfoIconsConfig|nil
---@field highlights  LvimLspInfoHighlightsConfig|nil

---@class LvimLspEfmConfig
---@field filetypes  string[]  Filetypes EFM should handle even when no tool config is registered
---@field executable string    EFM binary name used for PATH checks (default: "efm-langserver")

---@class LvimLspCommandsConfig

---@class LvimLspDiagnosticSignsConfig
---@field error string|nil
---@field warn  string|nil
---@field hint  string|nil
---@field info  string|nil

---@class LvimLspDiagnosticsConfig
---@field popup_title     string    Title shown in the floating diagnostics window (default: "Diagnostics")
---@field show_line       fun()|nil  Override for LspShowDiagnosticCurrent (default: vim.diagnostic.open_float)
---@field goto_next       fun()|nil  Override for LspShowDiagnosticNext    (default: vim.diagnostic.jump({ count = 1 }))
---@field goto_prev       fun()|nil  Override for LspShowDiagnosticPrev    (default: vim.diagnostic.jump({ count = -1 }))
---@field virtual_text    boolean|nil
---@field virtual_lines   boolean|nil
---@field underline       boolean|nil
---@field severity_sort   boolean|nil
---@field update_in_insert boolean|nil
---@field signs           LvimLspDiagnosticSignsConfig|nil

---@class LvimLspFeaturesConfig
---@field document_highlight boolean
---@field auto_format         boolean
---@field inlay_hints         boolean

---@class LvimLspCodeLensConfig
---@field enabled boolean

---@class LvimLspFormConfig
---@field after_apply string  "Stay" | "Close"

---@class LvimLspProgressPanelConfig
---@field name      string|nil  Header bar text (default: "LSP Progress")
---@field icon      string|nil  Header icon
---@field header_hl string|nil  Highlight group for the header bar

---@class LvimLspProgressHighlightsConfig
---@field icon       string|nil  Highlight for spinner/done icon (default: "Question")
---@field server     string|nil  Highlight for server name      (default: "Title")
---@field title      string|nil  Highlight for in-progress title (default: "WarningMsg")
---@field done       string|nil  Highlight for done title/icon  (default: "Constant")
---@field message    string|nil  Highlight for message text     (default: "Comment")
---@field percentage string|nil  Highlight for percentage value (default: "Special")

-- The engine's DATA config only sets enabled/ignore/done_ttl. The remaining fields
-- (spinner/done_icon/render_limit/panel/highlights) are UI options injected by lvim-lsp —
-- documented here as optional because they populate this same table at setup, with their
-- defaults living in lvim-lsp, not the engine.
---@class LvimLspProgressConfig
---@field enabled      boolean                            Enable/disable the progress subsystem (default: true)
---@field ignore       string[]                           Server names to suppress (default: {})
---@field done_ttl     integer                            Ms to keep a completed entry visible (default: 5000)
---@field spinner      string[]|nil                       (lvim-lsp) Animation frames cycled during active progress
---@field done_icon    string|nil                         (lvim-lsp) Icon shown when a token completes
---@field render_limit integer|nil                        (lvim-lsp) Max concurrent entries in the panel
---@field panel        LvimLspProgressPanelConfig|nil     (lvim-lsp) Progress panel header appearance
---@field highlights   LvimLspProgressHighlightsConfig|nil (lvim-lsp) Per-element highlight groups

---@alias LvimLspTool string | { [1]: string, bin: string }

---@class LvimLspFileTypeEntry
---@field filetypes  string[]
---@field lsp        LvimLspTool[]|nil
---@field formatters LvimLspTool[]|nil
---@field linters    LvimLspTool[]|nil
---@field debuggers  LvimLspTool[]|nil
---@field tools      LvimLspTool[]|nil  Generic tools the filetype needs that are NOT an LSP / formatter / linter / debugger (compilers, runtimes, build/test helpers). Install-only: offered by the installer, never started as a server or wired to EFM.

---@class LvimLspMenuConfig
---@field title    string|nil
---@field subtitle string|nil

---@class LvimLspMenusConfig
---@field toggle_servers        LvimLspMenuConfig
---@field toggle_servers_buffer LvimLspMenuConfig
---@field restart               LvimLspMenuConfig
---@field reattach              LvimLspMenuConfig
---@field declined              LvimLspMenuConfig

---@class LvimLspProjectTabConfig
---@field label string
---@field icon  string|nil

---@class LvimLspProjectTabsConfig
---@field servers    LvimLspProjectTabConfig
---@field formatters LvimLspProjectTabConfig
---@field linters    LvimLspProjectTabConfig
---@field filetypes  LvimLspProjectTabConfig
---@field global     LvimLspProjectTabConfig

---@class LvimLspProjectConfig
---@field title_icon string|nil
---@field tabs       LvimLspProjectTabsConfig

---@class LvimLspInfoHighlightsConfig
---@field icon       string|nil
---@field server     string|nil
---@field section    string|nil
---@field key        string|nil
---@field value      string|nil
---@field config_key string|nil
---@field separator  string|nil
---@field linter     string|nil
---@field formatter  string|nil
---@field tool       string|nil
---@field buffer     string|nil
---@field fold       string|nil

---@class LvimLspConfig
---@field file_types          table<string, LvimLspFileTypeEntry>  REQUIRED. module_key → entry
---@field server_config_dirs  string[]                  Lua require prefixes searched in order for server configs
---@field efm                 LvimLspEfmConfig
---@field info                LvimLspInfoConfig
---@field commands            LvimLspCommandsConfig
---@field menus               LvimLspMenusConfig
---@field project             LvimLspProjectConfig
---@field diagnostics         LvimLspDiagnosticsConfig
---@field features            LvimLspFeaturesConfig
---@field code_lens           LvimLspCodeLensConfig
---@field form                LvimLspFormConfig
---@field popup_global        table
---@field progress            LvimLspProgressConfig
---@field highlights          table<string, table>|nil  User overrides for LvimLsp* groups (applied on top of palette defaults)
---@field force              boolean                   true = always override theme-defined highlight groups (default: false)
---@field build              fun():table<string,table> Returns fresh LvimLsp* highlight definitions from the current palette
---@field on_attach           fun(client:any,bufnr:integer)|nil  Global on_attach called for every server
---@field on_dir_change       fun()|nil                 Called on DirChanged after stop_servers (e.g. fidget clear)
---@field startup_delay_ms    integer                   Defer ms before autocmds fire (default: 100)
---@field dir_change_delay_ms integer                   Defer ms before project-cleanup runs (default: 5000)
---@field notify              LvimLspNotifyConfig
---@field debug               LvimLspDebugConfig
---@field dap_local_fn        fun()|nil                 When set, adds :LvimLsp dap subcommand

local lsp = require("lvim-ls.config.lsp")
local features = require("lvim-ls.config.features")
local progress = require("lvim-ls.config.progress")
local message = require("lvim-ls.config.message")

---@type LvimLspConfig
local M = vim.tbl_deep_extend("force", lsp, features, progress, message) --[[@as LvimLspConfig]]
return M
