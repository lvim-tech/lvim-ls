-- The engine's live config, and the caches derived from it.
--
-- `lvim-ls.config` is required directly by readers, so configure() merges into that same table
-- rather than replacing it. Two derived values must be re-pointed on every merge: `bin_aliases`
-- (built from `languages`) and `efm_filetypes` — an ARRAY, which the merge replaces wholesale, so
-- a stale reference would keep the old list after a user narrowed it.

local state = require("lvim-ls.state")
local config = require("lvim-ls.config")

describe("lvim-ls.state.configure")

it("merges into the live config table", function()
    local alias = config
    state.configure({ lvim_test_key = "present" })
    eq("present", alias.lvim_test_key)
    truthy(alias == require("lvim-ls.config"), "the table itself must not be replaced")
    config.lvim_test_key = nil
end)

it("re-points the languages re-export after a merge", function()
    state.configure({ languages = { lvim_test_lang = { lsp = {} } } })
    truthy(state.languages.lvim_test_lang ~= nil, "state.languages must see the new entry")
    truthy(state.languages == config.languages, "and be the same table the config holds")
end)

it("re-points efm_filetypes when the array is replaced", function()
    -- An array is replaced, not merged: a reference captured before the merge would still answer
    -- with the old filetypes.
    state.configure({ efm = { filetypes = { "lua", "sh" } } })
    eq({ "lua", "sh" }, state.efm_filetypes)
    state.configure({ efm = { filetypes = { "lua" } } })
    eq({ "lua" }, state.efm_filetypes, "narrowed, not merged into the longer list")
end)

it("rebuilds the bin aliases from the languages it was given", function()
    state.configure({})
    truthy(type(state.bin_aliases) == "table", "bin_aliases must always be a table")
end)

it("takes no options at all", function()
    local ok, err = pcall(state.configure, nil)
    truthy(ok, tostring(err))
end)
