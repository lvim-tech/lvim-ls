-- lvim-ls: LSP core defaults.
-- file_types, server_config_dirs, EFM, lifecycle callbacks and timing.
--
---@module "lvim-ls.config.lsp"

return {
    file_types = {},
    server_config_dirs = {},
    commands = {},

    efm = {
        filetypes = {},
        executable = "efm-langserver",
    },

    on_attach = nil,
    on_dir_change = nil,
    startup_delay_ms = 100,
    dir_change_delay_ms = 5000,
    start_debounce_ms = 4000,
    dap_local_fn = nil,
}
