---@diagnostic disable: lowercase-global

lib.locale()

Core = {
    config = require 'config.shared',
    isServer = IsDuplicityVersion(),
}

Core.env = require 'modules.env'
Core.utils = require 'modules.utils'
Core.math = require 'modules.math'

---@type table<string, fun(...): any>
Core.db = {}

---@type fun()[]
local readyCallbacks = {}
local isReady = false

---Runs fn once every base/server file has been loaded. Load order inside the
---manifest globs is not guaranteed, so anything that reaches across files (the
---db layer in player/db.lua in particular) has to wait for this instead of
---running at file scope.
---@param fn fun()
function Core.onReady(fn)
    if isReady then
        return fn()
    end

    readyCallbacks[#readyCallbacks + 1] = fn
end

function Core.markReady()
    if isReady then return end

    isReady = true

    for index = 1, #readyCallbacks do
        local ok, err = pcall(readyCallbacks[index])

        if not ok then
            lib.print.error(('[core] ready callback failed: %s'):format(err))
        end
    end

    table.wipe(readyCallbacks)
end

---Core owns the `users` table and stores identifiers WITH their prefix
---("license:abc...") and identifiers are matched using their full values.
---name from the part before the colon and then matches the whole string.
---Core.utils.getIdentifiers strips prefixes, so every core read or write of
---users.license has to put it back -- otherwise the same player gets a
---second row and a split identity.
---@param license string?
---@return string?
function Core.toPrefixedLicense(license)
    if type(license) ~= 'string' or license == '' then
        return nil
    end

    return license:find('^license:') and license or ('license:' .. license)
end

---The same rule applies to the other identifier columns: license2,
---fivem and discord are all stored with their prefix intact.
---@param kind string
---@param value string?
---@return string?
function Core.toPrefixedIdentifier(kind, value)
    if type(value) ~= 'string' or value == '' then
        return nil
    end

    return value:find('^' .. kind .. ':') and value or ('%s:%s'):format(kind, value)
end

---@param username string
---@return boolean valid
---@return string? reason
function Core.isUsernameShapeValid(username)
    if type(username) ~= 'string' then
        return false, 'Username must be text.'
    end

    local length = #username

    if length < Core.config.username.minLength then
        return false, ('Username must be at least %s characters.'):format(Core.config.username.minLength)
    end

    if length > Core.config.username.maxLength then
        return false, ('Username must be at most %s characters.'):format(Core.config.username.maxLength)
    end

    if not username:match('^[%w_]+$') then
        return false, 'Username may only contain letters, numbers and underscores.'
    end

    return true
end

return Core
