-- lvim-ls: log-level utilities for consistent level handling across the plugin.
--
---@module "lvim-ls.utils.levels"

local M = {}

-- Level constants (TRACE .. OFF), ascending by severity.
M.TRACE = 0
M.DEBUG = 1
M.INFO = 2
M.WARN = 3
M.ERROR = 4
M.OFF = 5

local LEVELS = {
    TRACE = M.TRACE,
    DEBUG = M.DEBUG,
    INFO = M.INFO,
    WARN = M.WARN,
    ERROR = M.ERROR,
    OFF = M.OFF,
}

---@type table<integer,string>
local LEVEL_NAMES = nil

--- Initialize level names mapping
local function init_level_names()
    if LEVEL_NAMES then
        return
    end

    LEVEL_NAMES = {}
    for name, num in pairs(LEVELS) do
        LEVEL_NAMES[num] = name
    end
end

--- Validate level number
---@param level integer Level number to validate
---@return boolean
local function is_valid_level_number(level)
    if type(level) ~= "number" then
        return false
    end

    -- Initialize LEVEL_NAMES if needed
    init_level_names()

    return LEVEL_NAMES[level] ~= nil
end

--- Normalize level string to uppercase
---@param level_str string Level string
---@return string
local function normalize_level_string(level_str)
    if type(level_str) ~= "string" then
        return ""
    end
    return level_str:upper()
end

--- Convert input to level number
---@param input string|integer|nil Log level as string, number, or nil
---@return integer
function M.to_level_number(input)
    if input == nil then
        return M.INFO
    end

    if type(input) == "string" then
        local normalized = normalize_level_string(input)
        return LEVELS[normalized] or M.INFO
    end

    if type(input) == "number" and is_valid_level_number(input) then
        return input
    end

    return M.INFO
end

--- Check if current level should be shown based on minimum level
---@param current_level string|integer|nil Current log level
---@param min_level     string|integer|nil Minimum required level
---@return boolean
function M.should_show(current_level, min_level)
    local current = M.to_level_number(current_level)
    local min = M.to_level_number(min_level)
    return current >= min and current < M.OFF
end

--- Get level name from level number
---@param level_num integer Log level number
---@return string
function M.get_level_name(level_num)
    if level_num == nil then
        return "UNKNOWN"
    end

    init_level_names()
    return LEVEL_NAMES[level_num] or tostring(level_num)
end

return M
