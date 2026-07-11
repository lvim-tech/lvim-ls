-- lvim-ls: LSP progress tracker (DATA only — UI-agnostic).
-- Subscribes to the LspProgress autocmd (Neovim ≥ 0.10), accumulates per-token
-- state, and notifies listeners on change. Rendering (the panel / spinner) lives
-- in the UI plugin: lvim-lsp/ui/progress.lua subscribes via on_change().
--
---@module "lvim-ls.core.progress"

local state = require("lvim-ls.state")
local M = {}

-- Tracks active tokens: client_id → token → ProgressEntry
---@type table<integer, table<string|integer, table>>
local _tokens = {}
local _suppressed = false
---@type fun()[]
local _listeners = {}

---@return table  data progress config (enabled / ignore / done_ttl)
local function cfg()
    return state.config.progress or {}
end

--- Notify all listeners that progress state changed.
local function fire()
    for _, fn in ipairs(_listeners) do
        pcall(fn)
    end
end

--- Register a callback fired whenever progress state changes (for the UI to render).
---@param fn fun()
function M.on_change(fn)
    _listeners[#_listeners + 1] = fn
end

--- Count tokens that are still in progress (not done).
---@return integer
function M.active()
    local n = 0
    for _, tokens in pairs(_tokens) do
        for _, t in pairs(tokens) do
            if not t.done then
                n = n + 1
            end
        end
    end
    return n
end

--- Flat list of all tracked progress entries (active + done-pending) — for the UI.
---@return table[]
function M.items()
    local out = {}
    for _, tokens in pairs(_tokens) do
        for _, t in pairs(tokens) do
            out[#out + 1] = t
        end
    end
    return out
end

-- ── LspProgress handler ───────────────────────────────────────────────────────

---@param ev table  Autocmd event (ev.data = { client_id, params })
local function handle_progress(ev)
    if _suppressed then
        return
    end
    local client_id = ev.data and ev.data.client_id
    local params = ev.data and ev.data.params
    if not client_id or not params then
        return
    end
    local client = vim.lsp.get_client_by_id(client_id)
    if not client then
        return
    end
    for _, name in ipairs(cfg().ignore or {}) do
        if client.name == name then
            return
        end
    end
    local token = params.token
    local value = params.value
    if not token or not value then
        return
    end

    _tokens[client_id] = _tokens[client_id] or {}

    if value.kind == "begin" then
        _tokens[client_id][token] = {
            server_name = client.name,
            title = value.title,
            message = value.message,
            percentage = value.percentage,
            done = false,
        }
        fire()
    elseif value.kind == "report" then
        local t = _tokens[client_id][token]
        if t then
            t.message = value.message or t.message
            t.percentage = value.percentage or t.percentage
            fire()
        end
    elseif value.kind == "end" then
        local t = _tokens[client_id][token]
        if not t then
            return
        end
        t.done = true
        t.message = value.message or "Completed"
        t.percentage = nil
        fire()
        -- Keep the "done" state visible briefly, then drop it — but only if it is STILL the
        -- same finished entry. A reused token that began a fresh cycle before this TTL fired
        -- replaced `t` with a new table (identity differs), and must not be killed here.
        vim.defer_fn(function()
            local bucket = _tokens[client_id]
            if bucket and bucket[token] == t then
                bucket[token] = nil
                if vim.tbl_isempty(bucket) then
                    _tokens[client_id] = nil
                end
                fire()
            end
        end, cfg().done_ttl or 5000)
    end
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Initialise the progress subsystem (attaches the LSP autocmds). Called once from
--- lvim-ls. The UI registers its renderer separately via on_change().
---@return nil
function M.setup()
    if cfg().enabled == false then
        return
    end
    if vim.fn.exists("##LspProgress") == 0 then
        return
    end
    local aug = vim.api.nvim_create_augroup("LvimLspProgress", { clear = true })
    vim.api.nvim_create_autocmd("LspProgress", {
        group = aug,
        callback = handle_progress,
    })
    vim.api.nvim_create_autocmd("LspDetach", {
        group = aug,
        callback = function(ev)
            local cid = ev.data and ev.data.client_id
            if not cid then
                return
            end
            vim.schedule(function()
                -- LspDetach also fires when a SINGLE buffer detaches from a client that is
                -- still attached (and progressing) elsewhere. Only wipe the client's tokens
                -- once it is truly gone — no client, or no buffers left attached.
                local client = vim.lsp.get_client_by_id(cid)
                if client and next(client.attached_buffers or {}) then
                    return
                end
                if _tokens[cid] then
                    _tokens[cid] = nil
                    fire()
                end
            end)
        end,
    })
end

--- Toggle suppression of progress tracking (events are discarded while on).
---@param bool boolean
---@return nil
function M.suppress(bool)
    _suppressed = bool
end

--- Clear all tracked progress tokens (the UI clears its panel via on_change).
---@return nil
function M.clear()
    _tokens = {}
    fire()
end

return M
