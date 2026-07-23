-- lvim-ls: bootstrap — registers autocommands and the reattach command.
-- Scans the filetype of every newly-opened buffer and calls
-- manager.ensure_lsp_for_buffer() for each compatible, non-disabled server.
-- Also wires the DirChanged cleanup and an initial sweep of already-open buffers.
--
---@module "lvim-ls.core.bootstrap"

local state = require("lvim-ls.state")
local lsp_manager = require("lvim-ls.core.manager")
local project = require("lvim-ls.core.project")
local features = require("lvim-ls.core.features")
local data = require("lvim-ls.data")

local M = {}

--- Inspects the filetype of `bufnr`, finds every server that supports it, and
--- attaches non-disabled servers.  EFM is attached when the filetype has a
--- registered tool config or is listed in state.efm_filetypes.
---@param bufnr integer
function M.attach_lsp_to_buffer(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    local ft = vim.bo[bufnr].filetype
    if not ft or ft == "" then
        return
    end

    local matches = {}
    for key, entry in pairs(state.languages) do
        if vim.tbl_contains(entry.filetypes or {}, ft) then
            table.insert(matches, key)
        end
    end

    for _, match in ipairs(matches) do
        lsp_manager.ensure_lsp_for_buffer(match, bufnr)
    end

    -- Attach EFM when the filetype has a registered tool config or is in efm_filetypes
    if state.efm_configs[ft] or vim.tbl_contains(state.efm_filetypes, ft) then
        if
            not lsp_manager.is_server_disabled_globally("efm")
            and not lsp_manager.is_server_disabled_for_buffer("efm", bufnr)
        then
            lsp_manager.ensure_lsp_for_buffer("efm", bufnr)
        end
    end
end

--- Apply saved per-filetype editor options (.lvim/ls/filetypes/<ft>.lua) to `bufnr`.
---@param bufnr integer
local function apply_ft_settings(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    local ft = vim.bo[bufnr].filetype
    if not ft or ft == "" then
        return
    end

    local root = vim.uv.cwd() or vim.fn.getcwd()
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
        if client.config and client.config.root_dir then
            root = client.config.root_dir
            break
        end
    end

    local settings = project.load_ft(root, ft)
    if vim.tbl_isempty(settings) then
        return
    end
    for k, v in pairs(settings) do
        pcall(function()
            vim.bo[bufnr][k] = v
        end)
    end
end

--- Detach and stop every LSP client backed by the just-removed tool `name`.
--- Fired via lvim-pkg's "removing" event BEFORE the binary is deleted, so in-flight LSP
--- responses don't try to apply edits to non-modifiable buffers (E21) and the server
--- doesn't crash on missing files; the "removed" event repeats it for any straggler.
---@param name string  lvim-pkg / Mason package name
local function on_tool_removed(name)
    if not name or name == "" then
        return
    end
    -- The tool's managed install directory, to match a client's resolved binary path;
    -- falls back to matching by client name when lvim-pkg or the path is unavailable.
    local ok, pkg = pcall(require, "lvim-pkg")
    local pkg_dir = ok and type(pkg.package_path) == "function" and pkg.package_path(name) or nil
    for _, client in ipairs(vim.lsp.get_clients()) do
        local cmd = client.config and client.config.cmd
        local exe = type(cmd) == "table" and cmd[1] or ""
        if client.name == name or (pkg_dir and exe ~= "" and vim.startswith(exe, pkg_dir)) then
            -- Detach only from buffers actually attached to this client.
            for bufnr in pairs(client.attached_buffers or {}) do
                if vim.api.nvim_buf_is_valid(bufnr) then
                    pcall(vim.lsp.buf_detach_client, bufnr, client.id)
                end
            end
            pcall(client.stop, client)
        end
    end
end

--- Registers autocommands and performs an initial sweep of already-loaded
--- buffers so LSP servers attach immediately on startup.
function M.init()
    -- Contribute LSP/tool requirements to the unified install prompt. Soft dependency:
    -- the engine keeps working as a standalone plugin without lvim-pkg / the installer.
    local pkg_ok, pkg = pcall(require, "lvim-pkg")
    if pkg_ok then
        pkg.register_provider("lsp", function(ft)
            return data.items_for_ft(ft)
        end)
        -- React to installer events (the installer never requires lvim-ls directly).
        pkg.on("installing", function(active)
            lsp_manager.set_installation_status(active)
        end)
        -- Stop an LSP client BEFORE lvim-pkg deletes its tool's binary (avoids crashes /
        -- stale in-flight responses), then again after, for any straggler. Mason-kind only.
        pkg.on("removing", function(kind, name)
            if kind == "mason" then
                on_tool_removed(name)
            end
        end)
        pkg.on("removed", function(kind, name)
            if kind == "mason" then
                on_tool_removed(name)
            end
        end)
    end

    local group = vim.api.nvim_create_augroup("LvimLspEnable", { clear = true })
    local startup = state.config.startup_delay_ms
    local dir_ms = state.config.dir_change_delay_ms

    vim.defer_fn(function()
        -- Attach when Neovim sets the filetype on a buffer
        vim.api.nvim_create_autocmd("FileType", {
            group = group,
            callback = function(args)
                M.attach_lsp_to_buffer(args.buf)
                apply_ft_settings(args.buf)
            end,
        })

        -- Re-check on BufEnter / BufReadPost with a short delay so the filetype
        -- option is guaranteed to be set before we inspect it
        vim.api.nvim_create_autocmd({ "BufEnter", "BufReadPost" }, {
            group = group,
            callback = function(args)
                local bufnr = args.buf
                vim.defer_fn(function()
                    if vim.api.nvim_buf_is_valid(bufnr) then
                        M.attach_lsp_to_buffer(bufnr)
                        apply_ft_settings(bufnr)
                    end
                end, 100)
            end,
        })

        -- Prune per-buffer / per-client bookkeeping so it can't grow unbounded.
        -- LspDetach: clear the buffer's feature augroup once no LSP client remains, and drop
        -- a fully-exited client's stale ids from the manager's clients_by_root cache.
        vim.api.nvim_create_autocmd("LspDetach", {
            group = group,
            callback = function(ev)
                local buf = ev.buf
                local cid = ev.data and ev.data.client_id
                vim.schedule(function()
                    if not vim.api.nvim_buf_is_valid(buf) or #vim.lsp.get_clients({ bufnr = buf }) == 0 then
                        features.clear_buffer_features(buf)
                    end
                    if cid and not vim.lsp.get_client_by_id(cid) then
                        lsp_manager.prune_client(cid)
                    end
                end)
            end,
        })

        -- BufWipeout: drop the buffer's per-buffer disable overrides and feature augroup.
        vim.api.nvim_create_autocmd("BufWipeout", {
            group = group,
            callback = function(ev)
                state.disabled_for_buffer[ev.buf] = nil
                features.clear_buffer_features(ev.buf)
            end,
        })

        -- Stop servers from other projects after a directory change
        vim.api.nvim_create_autocmd("DirChanged", {
            pattern = "*",
            group = group,
            callback = function()
                vim.defer_fn(function()
                    lsp_manager.stop_servers_for_old_project()
                    if state.config.on_dir_change then
                        pcall(state.config.on_dir_change)
                    end
                end, dir_ms)
            end,
            desc = "Stop LSP servers from other projects on directory change",
        })

        -- Attach to any buffers that were already open before init() ran
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype ~= "" then
                M.attach_lsp_to_buffer(bufnr)
                apply_ft_settings(bufnr)
            end
        end
    end, startup)
end

return M
