-- lvim-ls plugin guard.
-- Nothing auto-runs; lvim-ls is an engine library driven via require("lvim-ls.*").
-- This file exists so the plugin manager recognises the plugin.
if vim.g.loaded_lvim_ls then
	return
end
vim.g.loaded_lvim_ls = true
