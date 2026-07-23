-- lvim-ls: shared RUNTIME state — replaces all _G.lsp_* and _G.LVIM.* globals.
-- All other modules read/write their runtime bookkeeping through this table so that no
-- global namespace pollution occurs and the plugin remains composable.
--
-- The live CONFIG is NOT owned here — it lives in `lvim-ls.config` (the canonical config
-- module). `M.config` below is a back-compat RE-EXPORT of that exact table (a stable alias
-- external consumers such as lvim-lsp and the user config read as `lvim-ls.state.config`).
-- `M.configure()` merges user options INTO the live config table in place, so both this
-- re-export and every `require("lvim-ls.config")` reader always see the effective values.
--
---@module "lvim-ls.state"

---@class LvimLspState
---@field config              LvimLspConfig            Back-compat re-export of the live `lvim-ls.config` table
---@field languages          table<string, LvimLspLanguageEntry>  Live ref to config.languages (module_key → entry)
---@field efm_filetypes       string[]                 Live ref to config.efm.filetypes
---@field bin_aliases         table<string, string>
---@field clients_by_root     table<string, table<string, integer>>
---@field start_attempts      table<string, table<string, integer>>  server → root → uv.now() of last spawn attempt (spawn debounce)
---@field start_failed        table<string, table<string, boolean>>  server → root → true when the server crashed on startup (auto-retry latched off)
---@field disabled_servers    table<string, boolean>
---@field disabled_for_buffer table<integer, table<string, boolean>>
---@field efm_configs         table<string, table[]>
---@field installation_in_progress boolean
---@field not_in_registry     table<string, boolean>

local config = require("lvim-ls.config")
local ok_utils, utils = pcall(require, "lvim-utils.utils")

local M = {}

-- ── Live config (re-export) ───────────────────────────────────────────────────

--- Back-compat re-export of the live config. Source of truth is `require("lvim-ls.config")`;
--- configure() merges into it in place, so this reference always reflects effective values.
---@type LvimLspConfig
M.config = config

--- Live references into the config that the runtime readers (core.manager, core.bootstrap) access directly as
--- `state.languages` / `state.efm_filetypes`. Set here and RE-POINTED by configure(): `languages` is a map
--- (merge recurses in place) but `efm.filetypes` is an ARRAY the merge REPLACES, so the ref must be refreshed.
---@type table<string, LvimLspLanguageEntry>
M.languages = config.languages or {}
---@type string[]
M.efm_filetypes = (config.efm and config.efm.filetypes) or {}

-- ── LSP lifecycle state ───────────────────────────────────────────────────────

--- Maps server_name → root_dir → client_id; one client reused per project root
M.clients_by_root = {}

--- Maps server_name → root_dir → uv.now() of the last spawn ATTEMPT. Used to debounce the
--- FileType / BufEnter / BufReadPost / startup-sweep triggers so a server with no live client
--- (still spawning, or one that crashed on startup) is not launched again within
--- config.start_debounce_ms — otherwise a fast-crashing server reports its error once per trigger.
---@type table<string, table<string, integer>>
M.start_attempts = {}

--- Maps server_name → root_dir → true once a spawned client EXITED abnormally BEFORE it initialized
--- (crashed on startup, e.g. jdtls on a too-old JVM). While latched, the auto-attach triggers stop
--- re-spawning that (server, root) — so a broken server reports its error ONCE, not on every BufEnter.
--- Cleared on a successful `on_init`, an explicit restart, or a tool reinstall (and reset each session).
---@type table<string, table<string, boolean>>
M.start_failed = {}

--- Server names disabled globally (across all buffers)
M.disabled_servers = {}

--- Per-buffer server disable overrides: bufnr → server_name → boolean
M.disabled_for_buffer = {}

--- Per-filetype EFM tool configs accumulated from language modules
M.efm_configs = {}

--- True while a Mason installation is in progress
M.installation_in_progress = false

--- Dep names that do not exist in the Mason registry.
--- Once a name lands here it is permanently skipped — no re-prompting.
---@type table<string, boolean>
M.not_in_registry = {}

-- ── Derived caches ────────────────────────────────────────────────────────────

--- Maps Mason package name → installed binary name for tools that differ.
--- Derived from the `bin` fields in the live config's languages; rebuilt by configure().
---@type table<string, string>
M.bin_aliases = {}

--- Scan the live config's languages entries and build the { package = bin } alias map.
---@param languages table<string, LvimLspLanguageEntry>
---@return table<string, string>
local function build_bin_aliases(languages)
    local aliases = {}
    local function scan(list)
        for _, tool in ipairs(list or {}) do
            if type(tool) == "table" and tool[1] and tool.bin then
                aliases[tool[1]] = tool.bin
            end
        end
    end
    for _, entry in pairs(languages) do
        scan(entry.lsp)
        scan(entry.formatters)
        scan(entry.linters)
        scan(entry.debuggers)
        scan(entry.tools)
    end
    return aliases
end

M.bin_aliases = build_bin_aliases(config.languages)

--- Validate the shape of `languages` and collect human-readable problems. Catches the
--- common config mistakes (wrong types) so they surface as a warning instead of silently
--- no-op'ing when a server is looked up by filetype.
---@param languages any
---@return string[]
local function validate_languages(languages)
    local problems = {}
    if type(languages) ~= "table" then
        return { "languages must be a table" }
    end
    local function check_tool_list(name, key, list)
        if list == nil then
            return
        end
        if not vim.islist(list) then
            problems[#problems + 1] = ("%s.%s must be a list"):format(name, key)
            return
        end
        for _, tool in ipairs(list) do
            local t = type(tool)
            if t ~= "string" and not (t == "table" and type(tool[1]) == "string") then
                problems[#problems + 1] = ("%s.%s entries must be a string or { name, bin = … }"):format(name, key)
                break
            end
        end
    end
    for name, entry in pairs(languages) do
        name = tostring(name)
        if type(entry) ~= "table" then
            problems[#problems + 1] = ("%s: entry must be a table"):format(name)
        else
            local fts = entry.filetypes
            if fts ~= nil and not vim.islist(fts) then
                problems[#problems + 1] = ("%s.filetypes must be a string list"):format(name)
            elseif vim.islist(fts) then
                for _, ft in ipairs(fts) do
                    if type(ft) ~= "string" then
                        problems[#problems + 1] = ("%s.filetypes must contain only strings"):format(name)
                        break
                    end
                end
            end
            check_tool_list(name, "lsp", entry.lsp)
            check_tool_list(name, "formatters", entry.formatters)
            check_tool_list(name, "linters", entry.linters)
            check_tool_list(name, "debuggers", entry.debuggers)
            check_tool_list(name, "tools", entry.tools)
        end
    end
    return problems
end

--- Merge user config into the live config IN PLACE and refresh derived caches.
--- Uses lvim-utils.utils.merge (clean array replace); falls back to an in-place
--- tbl_deep_extend copy-back only when lvim-utils is unavailable, so the re-export
--- and every require("lvim-ls.config") reader keep pointing at the same live table.
---@param user_config LvimLspConfig
function M.configure(user_config)
    if ok_utils and utils.merge then
        utils.merge(config, user_config or {})
    elseif user_config then
        for k, v in pairs(vim.tbl_deep_extend("force", config, user_config)) do
            config[k] = v
        end
    end
    M.bin_aliases = build_bin_aliases(config.languages)
    -- Re-point the back-compat runtime refs — `efm.filetypes` is an array the merge may have replaced.
    M.languages = config.languages or {}
    M.efm_filetypes = (config.efm and config.efm.filetypes) or {}
    -- Surface malformed languages entries once, at configure time (lazy require avoids a
    -- load-time cycle with the notify util).
    local problems = validate_languages(config.languages)
    if #problems > 0 then
        require("lvim-ls.utils.notify")(
            ("lvim-ls config: %d languages issue(s):\n  %s"):format(#problems, table.concat(problems, "\n  ")),
            vim.log.levels.WARN
        )
    end
end

return M
