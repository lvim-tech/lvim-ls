-- lvim-ls: feature flag defaults.
-- Per-buffer hooks (document_highlight, auto_format, inlay_hints),
-- CodeLens lifecycle and vim.diagnostic configuration.
--
---@module "lvim-ls.config.features"

return {
    features = {
        document_highlight = false,
        auto_format = true,
        inlay_hints = true,
    },

    code_lens = {
        enabled = true,
    },

    -- SEMANTIC TOKENS. `debounce` is the delay (ms) the core waits after a change before asking the server for
    -- tokens. It is 200 by default — and that timer is where a Neovim bug lives: `STHighlighter:on_detach` drops
    -- the client's state WITHOUT stopping the pending timer, and `reset_timer` then reads `state.timer` with no
    -- nil guard. So any detach inside the debounce window (a project switch in lvim-space wipes the old
    -- project's buffers, which detaches their clients) throws
    -- `semantic_tokens.lua:790: attempt to index local 'state' (a nil value)` from a scheduled callback.
    -- `debounce = 0` means the request is sent straight away and NO timer is ever armed — nothing is left behind
    -- to fire on a dead state. The cost is a request per change instead of one per 200 ms; raise it back once
    -- the core guards the timer.
    semantic_tokens = {
        enabled = true,
        debounce = 0,
    },

    diagnostics = {
        popup_title = " Diagnostics",
        show_line = nil,
        goto_next = nil,
        goto_prev = nil,
        virtual_text = nil,
        virtual_lines = nil,
        underline = nil,
        severity_sort = nil,
        update_in_insert = nil,
        signs = nil,
    },
}
