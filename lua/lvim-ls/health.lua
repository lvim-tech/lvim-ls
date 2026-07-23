-- lvim-ls: :checkhealth lvim-ls
--
-- Checks the pieces the LSP ENGINE needs: built-in vim.lsp, the lvim-pkg data hub
-- (soft dependency — used for install-state checks and the requirement provider),
-- the EFM aggregator binary, the Mason bin directory where tool presence is probed,
-- and the engine config shape. UI is lvim-lsp's concern (see :checkhealth lvim-lsp).
--
---@module "lvim-ls.health"

local state = require("lvim-ls.state")

local M = {}

function M.check()
    local h = vim.health
    h.start("lvim-ls")

    -- ── core ──────────────────────────────────────────────────────────────────
    -- The engine uses ≥ 0.12 APIs (vim.lsp.codelens.enable(enable, filter),
    -- vim.lsp.inlay_hint.enable) so gate on 0.12, not 0.10.
    if vim.fn.has("nvim-0.12") == 1 and type(vim.lsp) == "table" and vim.lsp.start then
        h.ok("built-in vim.lsp available (Neovim >= 0.12)")
    else
        h.error("Neovim >= 0.12 with built-in vim.lsp is required")
    end

    -- ── lvim-pkg (soft dependency) ────────────────────────────────────────────
    local ok_pkg, pkg = pcall(require, "lvim-pkg")
    if ok_pkg and type(pkg.is_installed) == "function" then
        h.ok("lvim-pkg found (install-state checks + the unified install prompt)")
    else
        h.warn("lvim-pkg not found — falling back to a Mason bin-dir check; the install prompt is unavailable")
    end

    -- ── tool probes ───────────────────────────────────────────────────────────
    if vim.fn.executable("efm-langserver") == 1 then
        h.ok("efm-langserver — aggregates the registered formatters / linters")
    else
        h.info("efm-langserver not on PATH — installed on demand when a filetype needs a formatter/linter")
    end

    local mason_bin = vim.fn.stdpath("data") .. "/mason/bin"
    if vim.fn.isdirectory(mason_bin) == 1 then
        h.ok("Mason bin dir present: " .. mason_bin)
    else
        h.info("Mason bin dir not present yet (created when the first tool is installed)")
    end

    -- ── config shape ──────────────────────────────────────────────────────────
    local cfg = state.config or {}
    local ft_ok = type(cfg.languages) == "table"
    local dirs_ok = type(cfg.server_config_dirs) == "table"
    if ft_ok and dirs_ok then
        local n_ft = vim.tbl_count(cfg.languages)
        local n_dirs = #cfg.server_config_dirs
        h.ok(("config: %d languages entr(ies), %d server_config_dir(s)"):format(n_ft, n_dirs))
        if n_dirs == 0 then
            h.info("server_config_dirs is empty — server configs are injected by lvim-lsp at setup")
        end
    else
        h.warn("config: expected languages:table and server_config_dirs:string[] (injected via lvim-lsp.setup)")
    end

    -- ── runtime ───────────────────────────────────────────────────────────────
    if state.installation_in_progress then
        h.info("an install is in progress — server auto-start is paused until it completes")
    end
end

return M
