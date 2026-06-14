-- lvim-ls: requirement data for the unified installer prompt.
-- Reports which servers/tools a filetype needs but lacks, without installing or
-- showing any UI.  Consumed by lvim-pkg's provider registry so lvim-installer can
-- offer the missing Mason tools alongside treesitter parsers.
--
---@module "lvim-ls.data"

local manager = require("lvim-ls.core.manager")

local M = {}

--- Missing tools for filetype `ft`, grouped by the server that requires them.
---@param ft string
---@return table<string, string[]>  server_name → missing dependency names
function M.missing_for_ft(ft)
    local out = {}
    for _, server_name in ipairs(manager.get_compatible_lsp_for_ft(ft)) do
        local missing = manager.missing_tools_for_server(server_name)
        if #missing > 0 then
            out[server_name] = missing
        end
    end
    return out
end

--- Flat list of LvimPkgItem describing every missing Mason tool for `ft`.
--- Shape matches lvim-pkg's provider contract; the owning server is the `group`.
---@param ft string
---@return table[]
function M.items_for_ft(ft)
    local items = {}
    for server_name, tools in pairs(M.missing_for_ft(ft)) do
        for _, tool in ipairs(tools) do
            items[#items + 1] = { kind = "mason", name = tool, label = tool, group = server_name }
        end
    end
    return items
end

return M
