-- lvim-ls: LSP progress DATA defaults (behaviour only — the panel appearance lives
-- in lvim-lsp's UI config: lvim-lsp.state.config.progress).
return {
	progress = {
		-- Set to false to disable the entire progress subsystem.
		enabled = true,
		-- Server names to silently ignore (e.g. { "null-ls" }).
		ignore = {},
		-- Milliseconds to keep a "done" entry tracked before removing it.
		done_ttl = 5000,
	},
}
