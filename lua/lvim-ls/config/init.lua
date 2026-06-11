-- lvim-ls: default DATA configuration (engine only — no UI here).
-- Merges the data sections; UI config (ui/highlights) lives in lvim-lsp and is
-- injected at setup. Loaded once by state.lua; users override via lvim-lsp.setup(opts).

local lsp = require("lvim-ls.config.lsp")
local features = require("lvim-ls.config.features")
local progress = require("lvim-ls.config.progress")
local message = require("lvim-ls.config.message")

---@type LvimLspConfig
local M = vim.tbl_deep_extend("force", lsp, features, progress, message) --[[@as LvimLspConfig]]
return M
