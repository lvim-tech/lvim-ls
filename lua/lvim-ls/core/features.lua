-- lvim-ls: optional LSP feature setup.
-- Handles vim.diagnostic configuration, sign definitions, CodeLens lifecycle,
-- and per-buffer on_attach hooks (document_highlight, auto_format, inlay_hints).
--
---@module "lvim-ls.core.features"

local state = require("lvim-ls.state")
local notify = require("lvim-ls.utils.notify")
local project = require("lvim-ls.core.project")
local M = {}

local function code_lenses(bufnr)
    local raw = vim.lsp.codelens.get({ bufnr = bufnr }) or {}
    local out = {}
    for _, item in ipairs(raw) do
        local lens = item.lens or item
        if lens and lens.range then
            out[#out + 1] = lens
        end
    end
    return out
end

-- ── Diagnostics ───────────────────────────────────────────────────────────────

--- Applies state.config.diagnostics to vim.diagnostic and registers sign symbols.
--- Only sets options that are explicitly non-nil in the config.
function M.setup_diagnostics()
    local cfg = state.config.diagnostics

    local diag_opts = {}
    local keys = { "virtual_text", "virtual_lines", "underline", "severity_sort", "update_in_insert" }
    for _, k in ipairs(keys) do
        if cfg[k] ~= nil then
            diag_opts[k] = cfg[k]
        end
    end

    if cfg.signs then
        local text = {}
        local sev = vim.diagnostic.severity
        if cfg.signs.error then
            text[sev.ERROR] = cfg.signs.error
        end
        if cfg.signs.warn then
            text[sev.WARN] = cfg.signs.warn
        end
        if cfg.signs.hint then
            text[sev.HINT] = cfg.signs.hint
        end
        if cfg.signs.info then
            text[sev.INFO] = cfg.signs.info
        end
        if next(text) then
            diag_opts.signs = { text = text }
        end

        -- Legacy sign symbols for plugins that read the signcolumn directly
        if cfg.signs.error then
            vim.fn.sign_define("DiagnosticSignError", { text = cfg.signs.error, texthl = "DiagnosticError" })
        end
        if cfg.signs.warn then
            vim.fn.sign_define("DiagnosticSignWarn", { text = cfg.signs.warn, texthl = "DiagnosticWarn" })
        end
        if cfg.signs.hint then
            vim.fn.sign_define("DiagnosticSignHint", { text = cfg.signs.hint, texthl = "DiagnosticHint" })
        end
        if cfg.signs.info then
            vim.fn.sign_define("DiagnosticSignInfo", { text = cfg.signs.info, texthl = "DiagnosticInfo" })
        end
    end

    if next(diag_opts) then
        vim.diagnostic.config(diag_opts)
    end
end

-- ── CodeLens ──────────────────────────────────────────────────────────────────

--- Run the CodeLens on or nearest to the current cursor line.
--- Falls back to the first available lens in the buffer when none is on the cursor line.
---@return nil
function M.run_code_lens()
    if not state.config.code_lens.enabled then
        notify("CodeLens is disabled", vim.log.levels.WARN)
        return
    end
    local line = vim.api.nvim_win_get_cursor(0)[1] - 1
    local lenses = code_lenses(0)

    for _, lens in ipairs(lenses) do
        if lens.range.start.line == line then
            vim.lsp.codelens.run()
            return
        end
    end

    local closest, min_dist = nil, math.huge
    for _, lens in ipairs(lenses) do
        local d = math.abs(lens.range.start.line - line)
        if d < min_dist then
            min_dist = d
            closest = lens
        end
    end
    if closest then
        vim.api.nvim_win_set_cursor(0, { closest.range.start.line + 1, closest.range.start.character })
        vim.lsp.codelens.run()
    elseif #lenses == 0 then
        notify("No CodeLens found in this buffer", vim.log.levels.WARN)
    else
        notify("No CodeLens on current line", vim.log.levels.INFO)
    end
end

--- Bind the CodeLens double-click on an LSP-attached buffer.
---
--- BUFFER-LOCAL by design. A mouse mapping is process-wide and the LAST registration WINS, so binding
--- `<2-LeftMouse>` GLOBALLY (as this did) silently overrode the ecosystem's panel mouse-lock
--- (`lvim-utils.mouse`) — and this handler's `return "<2-LeftMouse>"` fall-through then ran nvim's NATIVE
--- double-click, which selects the WORD under the pointer. Inside a UI panel (the LSP outline, the file tree)
--- that replaced the row's full-width selection bar with a Visual patch over its label. CodeLens only ever
--- applies to a real, LSP-attached code buffer — which is exactly where this map belongs, and where it can no
--- longer reach a panel at all.
---@param bufnr integer
local function bind_codelens_click(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) or vim.b[bufnr].lvim_codelens_click then
        return
    end
    vim.b[bufnr].lvim_codelens_click = true
    vim.keymap.set("n", "<2-LeftMouse>", function()
        -- Buffer-local is NOT sufficient on its own, and this guard is NOT belt-and-suspenders. A mouse map is
        -- resolved against the CURRENT buffer, but the POINTER may be somewhere else entirely: clicking into the
        -- LSP outline while this code buffer is current fires THIS map — and the fall-through below
        -- (`return "<2-LeftMouse>"`) then runs nvim's NATIVE double-click, which selects the WORD under the
        -- pointer, i.e. inside the panel. Any mouse map that can fall through must first ask the mouse layer
        -- whether the pointer is over a panel.
        local ok, mouse = pcall(require, "lvim-utils.mouse")
        if ok and mouse.should_swallow() then
            return ""
        end
        if not state.config.code_lens.enabled then
            return "<2-LeftMouse>"
        end
        local line = vim.api.nvim_win_get_cursor(0)[1] - 1
        for _, lens in ipairs(code_lenses(0)) do
            if lens.range.start.line == line then
                vim.lsp.codelens.run()
                return ""
            end
        end
        return "<2-LeftMouse>"
    end, { buffer = bufnr, noremap = true, silent = true, expr = true })
end

--- Semantic tokens, per `config.semantic_tokens` — a ONE-TIME global setting, not per buffer.
---
--- `debounce` is why this exists. The core arms a `vim.defer_fn` timer per change, and `STHighlighter:on_detach`
--- drops the client's state WITHOUT stopping that timer, while `reset_timer` reads `state.timer` with no nil
--- guard. So a detach inside the debounce window — a project switch in lvim-space wipes the old project's
--- buffers, detaching their clients — leaves a timer that fires on a dead state and throws
--- `semantic_tokens.lua:790: attempt to index local 'state' (a nil value)`. With `debounce = 0` no timer is ever
--- armed: the request goes straight out, so there is nothing left behind to fire. Raise it once the core guards
--- the timer (the missing guard is a Neovim bug, not ours).
---
--- The debounce lives on the highlighter CLASS (its prototype default), which the core exports as
--- `vim.lsp.semantic_tokens.__STHighlighter` — so one assignment covers every buffer, with no deprecated call
--- (`semantic_tokens.start(…, { debounce })` is deprecated and warns).
function M.setup_semantic_tokens()
    local st = state.config.semantic_tokens
    if not st then
        return
    end
    if st.enabled == false then
        pcall(vim.lsp.semantic_tokens.enable, false)
        return
    end
    --- Write the debounce onto the highlighter CLASS (its prototype default), so every buffer inherits it.
    local function apply()
        local cls = vim.lsp.semantic_tokens.__STHighlighter --[[@as table?]]
        if type(cls) == "table" and type(st.debounce) == "number" then
            cls.debounce = st.debounce
        end
    end
    apply()
    -- ALSO on every attach: the semantic-tokens module is loaded LAZILY, so a value written during our own
    -- `setup()` can be handed back to a class table that is only created afterwards. Re-asserting on LspAttach
    -- costs one field assignment and makes the setting independent of load order.
    if not M._st_group then
        M._st_group = vim.api.nvim_create_augroup("LvimLsSemanticTokens", { clear = true })
        vim.api.nvim_create_autocmd("LspAttach", {
            group = M._st_group,
            callback = apply,
        })
    end
end

--- Initialise CodeLens based on state.config.code_lens.enabled.
--- Uses the native `vim.lsp.codelens.enable(enable, { bufnr })` API (Neovim ≥ 0.12).
--- Not pcall-wrapped: enable() never throws for a valid buffer, so a signature drift
--- surfaces loudly instead of silently no-op'ing (the historical CodeLens bug).
---@return nil
function M.setup_code_lens()
    local cfg = state.config.code_lens
    if not cfg then
        return
    end

    local function set_for_all_bufs(enabled)
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
                vim.lsp.codelens.enable(enabled, { bufnr = bufnr })
            end
        end
    end

    if cfg.enabled then
        set_for_all_bufs(true)
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
                bind_codelens_click(bufnr)
            end
        end
        local group = vim.api.nvim_create_augroup("LvimLspCodeLens", { clear = true })
        vim.api.nvim_create_autocmd("LspAttach", {
            group = group,
            callback = function(ev)
                if state.config.code_lens.enabled then
                    vim.lsp.codelens.enable(true, { bufnr = ev.buf })
                    bind_codelens_click(ev.buf)
                end
            end,
        })
        M._codelens_group = group
    else
        if M._codelens_group then
            pcall(vim.api.nvim_clear_autocmds, { group = M._codelens_group })
            M._codelens_group = nil
        end
        set_for_all_bufs(false)
    end

    -- Register commands (idempotent)
    if not M._commands_registered then
        M._commands_registered = true

        vim.api.nvim_create_user_command("LspCodeLensRun", function()
            M.run_code_lens()
        end, {})
    end
end

-- ── Per-buffer on_attach hooks ────────────────────────────────────────────────

--- Buffers whose feature augroup is already wired. ONE group per buffer (not per
--- client): the document-highlight / auto-format callbacks re-check LIVE client
--- capabilities, so a single group serves every client attached to the buffer (a
--- main server + efm) — instead of N formatting clients each installing their own
--- BufWritePre that then formats with ALL clients (the N×N save fan-out).
---@type table<integer, integer>  bufnr → augroup id
M._feature_groups = {}

---@param val boolean|fun():boolean|nil
---@return boolean
local function eval_flag(val)
    if type(val) == "function" then
        return val() == true
    end
    return val == true
end

--- Enable inlay hints for `bufnr`, honouring the project override. Applied per client
--- attach because the inlay-hint capability is per client, while the enabled state is
--- per buffer (so a restart re-pulls hints against the fresh client).
---@param client any
---@param bufnr  integer
---@param root   string|nil
local function apply_inlay_hints(client, bufnr, root)
    if not (vim.lsp.inlay_hint and client.server_capabilities.inlayHintProvider) then
        return
    end
    local feat = state.config.features
    local ih_global = feat and feat.inlay_hints
    if ih_global == nil then
        return
    end
    vim.schedule(function()
        local effective = ih_global
        if root then
            effective = project.get_feature(root, "inlay_hints", ih_global)
        end
        if eval_flag(effective) then
            -- A server restart re-attaches to an already-open buffer where inlay hints may still
            -- be enabled from the previous client; enable(true) is then a no-op and the stale
            -- hints linger until `:e`. Toggle off first to force a fresh request against the new
            -- client (so e.g. a flipped `Lua.hint.enable` takes effect on restart, not after :e).
            if vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }) then
                vim.lsp.inlay_hint.enable(false, { bufnr = bufnr })
            end
            vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
        end
    end)
end

--- Called from manager's on_attach for every client attached to `bufnr`.
--- Wires document_highlight + auto_format ONCE per buffer (capabilities re-checked live)
--- and applies inlay hints per client. Project config (.lvim-ls) overrides global features.
---@param client any
---@param bufnr  integer
function M.apply_buffer_features(client, bufnr)
    local feat = state.config.features
    if not feat then
        return
    end
    local root = type(client.config) == "table" and client.config.root_dir or nil

    apply_inlay_hints(client, bufnr, root)

    -- Buffer-scoped autocmds are created only on the FIRST attach for the buffer.
    if M._feature_groups[bufnr] then
        return
    end
    local group = vim.api.nvim_create_augroup("LvimLspFeatures_" .. bufnr, { clear = true })
    M._feature_groups[bufnr] = group

    -- Document highlight (no project override — always global)
    if feat.document_highlight then
        vim.api.nvim_create_autocmd("CursorHold", {
            buffer = bufnr,
            group = group,
            callback = function()
                for _, c in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
                    if c.server_capabilities.documentHighlightProvider then
                        vim.lsp.buf.document_highlight()
                        break
                    end
                end
            end,
        })
        vim.api.nvim_create_autocmd("CursorMoved", {
            buffer = bufnr,
            group = group,
            callback = function()
                for _, c in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
                    if c.server_capabilities.documentHighlightProvider then
                        vim.lsp.buf.clear_references()
                        break
                    end
                end
            end,
        })
    end

    -- Auto-format on save (project config overrides global). vim.lsp.buf.format already
    -- filters to the formatting-capable clients, so ONE BufWritePre covers main + efm.
    if feat.auto_format ~= nil then
        vim.api.nvim_create_autocmd("BufWritePre", {
            buffer = bufnr,
            group = group,
            callback = function()
                local effective = feat.auto_format
                if root then
                    effective = project.get_feature(root, "auto_format", feat.auto_format)
                end
                if eval_flag(effective) then
                    vim.lsp.buf.format({ bufnr = bufnr })
                end
            end,
        })
    end
end

--- Tear down the buffer's feature augroup — called when the last LSP client detaches or
--- the buffer is wiped, so M._feature_groups (and its autocmds) don't leak for dead buffers.
---@param bufnr integer
function M.clear_buffer_features(bufnr)
    local group = M._feature_groups[bufnr]
    if group then
        pcall(vim.api.nvim_del_augroup_by_id, group)
        M._feature_groups[bufnr] = nil
    end
end

--- Force a fresh inlay-hint request for `bufnr`. Neovim does NOT re-pull inlay hints when a server's
--- configuration changes (it only re-requests on a buffer edit or a server-side refresh), so a live
--- server-side toggle like lua_ls `Lua.hint.enable` would otherwise linger until `:e`. Toggling the
--- per-buffer state off→on clears the stale hints and issues a new request. No-op when hints are off.
---@param bufnr integer
function M.refresh_inlay_hints(bufnr)
    if not (vim.lsp.inlay_hint and type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr)) then
        return
    end
    local ok, enabled = pcall(vim.lsp.inlay_hint.is_enabled, { bufnr = bufnr })
    if not (ok and enabled) then
        return
    end
    vim.lsp.inlay_hint.enable(false, { bufnr = bufnr })
    vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
        end
    end)
end

return M
