---Server half of the appearance resource.
---
---Storage is NOT here: core owns `user_appearance` and exposes GetAppearance
---/ SaveAppearance, so this delegates rather than keeping a second copy that
---could disagree with the one the pause menu reads.
---
---What this file is actually for is the half a client cannot be trusted with
---— config/shared.lua's blacklist. That file ships to the client so the menu
---can grey entries out, but a client can send whatever drawable it likes, so
---every save is re-checked here before it is persisted. The `vip` and
---`groups` flags on a blacklist entry are the reason this cannot live
---client-side at all: only the server knows which of them a player satisfies.

local core = exports.core

local sharedConfig = require 'config.shared'
local allowedPeds = require 'data.peds'

---Blacklist keys map onto GTA's component and prop ids. `hair` is listed
---separately in the config because the menu treats it as its own tab, but on
---the ped it is just component 2.
---@type table<string, integer>
local COMPONENT_IDS = {
    masks = 1,
    hair = 2,
    upperBody = 3,
    lowerBody = 4,
    bags = 5,
    shoes = 6,
    scarfAndChains = 7,
    shirts = 8,
    bodyArmor = 9,
    decals = 10,
    jackets = 11,
}

---@type table<string, integer>
local PROP_IDS = {
    hats = 0,
    glasses = 1,
    ear = 2,
    watches = 6,
    bracelets = 7,
}

---@type table<string, true>
local pedWhitelist = {}

for index = 1, #allowedPeds do
    pedWhitelist[allowedPeds[index]] = true
end

local FEMALE_MODEL = 'mp_f_freemode_01'

-- ------------------------------------------------------------ entitlements ----

---@param source Source
---@return boolean
local function isVip(source)
    if IsPlayerAceAllowed(source --[[@as string]], 'appearance.vip') then
        return true
    end

    -- Falls back to core's item catalogue: a purchased VIP entitlement lands
    -- in the player's inventory rather than in an ace.
    return core:OwnsItem(source, 'vip') == true
end

---@param source Source
---@param groups string[]?
---@return boolean
local function inAnyGroup(source, groups)
    if not groups or #groups == 0 then
        return false
    end

    for index = 1, #groups do
        if IsPlayerAceAllowed(source --[[@as string]], ('group.%s'):format(groups[index])) then
            return true
        end
    end

    return false
end

---Whether a single blacklist entry still applies to this player. An entry
---with `vip` or `groups` is a restriction they can be exempt from; a plain
---entry applies to everyone.
---@param source Source
---@param entry table
---@return boolean
local function entryApplies(source, entry)
    if entry.vip and isVip(source) then
        return false
    end

    if entry.groups and inAnyGroup(source, entry.groups) then
        return false
    end

    return true
end

---@param list integer[]?
---@param value integer
---@return boolean
local function listContains(list, value)
    if not list then
        -- An entry with no drawables list blocks the whole category.
        return true
    end

    for index = 1, #list do
        if list[index] == value then
            return true
        end
    end

    return false
end

---@param source Source
---@param entries table[]?
---@param drawable integer
---@param texture integer?
---@return boolean
local function isBlocked(source, entries, drawable, texture)
    if not entries then
        return false
    end

    for index = 1, #entries do
        local entry = entries[index]

        if entryApplies(source, entry)
            and listContains(entry.drawables, drawable)
            -- No textures list means every texture of that drawable is out.
            and (entry.textures == nil or texture == nil or listContains(entry.textures, texture))
        then
            return true
        end
    end

    return false
end

-- -------------------------------------------------------------- validation ----

---@param appearance table
---@return 'male' | 'female'
local function getSex(appearance)
    return appearance.model == FEMALE_MODEL and 'female' or 'male'
end

---@param source Source
---@param appearance table
---@return boolean ok
---@return string? reason
local function validate(source, appearance)
    if type(appearance) ~= 'table' then
        return false, 'Invalid appearance.'
    end

    if appearance.model ~= nil and not pedWhitelist[appearance.model] then
        return false, 'That ped model is not allowed.'
    end

    local blacklist = sharedConfig.blacklist[getSex(appearance)]

    if not blacklist then
        return true
    end

    for key, componentId in pairs(COMPONENT_IDS) do
        local entries = key == 'hair' and blacklist.hair or (blacklist.components and blacklist.components[key])

        for _, component in pairs(appearance.components or {}) do
            if component.component_id == componentId
                and isBlocked(source, entries, component.drawable, component.texture)
            then
                return false, ('That %s option is not available to you.'):format(key)
            end
        end
    end

    for key, propId in pairs(PROP_IDS) do
        local entries = blacklist.props and blacklist.props[key]

        for _, prop in pairs(appearance.props or {}) do
            if prop.prop_id == propId
                and isBlocked(source, entries, prop.drawable, prop.texture)
            then
                return false, ('That %s option is not available to you.'):format(key)
            end
        end
    end

    return true
end

-- ------------------------------------------------------------------- api ----

---@param source Source
---@param appearance table
---@return boolean success
---@return string? error
local function saveAppearance(source, appearance)
    local ok, reason = validate(source, appearance)

    if not ok then
        core:Log('protection', ('%s (src %s) sent a blocked appearance: %s'):format(
            (core:GetPlayerData(source) or {}).username or 'unknown', source, reason
        ))

        return false, reason
    end

    if not core:SaveAppearance(source, appearance) then
        return false, 'Could not save your appearance.'
    end

    TriggerEvent('appearance:server:onSaved', source, appearance)

    return true
end

---@param appearance table
---@return boolean success
---@return string? error
lib.callback.register('appearance:server:save', function(source, appearance)
    return saveAppearance(source, appearance)
end)

---@return table?
lib.callback.register('appearance:server:get', function(source)
    return core:GetAppearance(source)
end)

---Only the blacklist entries that still bind this player, so the menu can
---grey out exactly what the save would refuse and nothing more.
---@return table
lib.callback.register('appearance:server:getBlacklist', function(source)
    local effective = { male = { components = {}, props = {}, hair = {} }, female = { components = {}, props = {}, hair = {} } }

    for sex, sexBlacklist in pairs(sharedConfig.blacklist) do
        local out = effective[sex]

        if out then
            for index = 1, #(sexBlacklist.hair or {}) do
                local entry = sexBlacklist.hair[index]

                if entryApplies(source, entry) then
                    out.hair[#out.hair + 1] = entry
                end
            end

            for key, entries in pairs(sexBlacklist.components or {}) do
                out.components[key] = {}

                for index = 1, #entries do
                    if entryApplies(source, entries[index]) then
                        out.components[key][#out.components[key] + 1] = entries[index]
                    end
                end
            end

            for key, entries in pairs(sexBlacklist.props or {}) do
                out.props[key] = {}

                for index = 1, #entries do
                    if entryApplies(source, entries[index]) then
                        out.props[key][#out.props[key] + 1] = entries[index]
                    end
                end
            end
        end
    end

    return effective
end)

---@return string[]
lib.callback.register('appearance:server:getPeds', function()
    return allowedPeds
end)

exports('GetAppearance', function(source)
    return core:GetAppearance(source)
end)

exports('SaveAppearance', saveAppearance)

---@param source Source
---@param appearance table
---@return boolean ok
---@return string? reason
exports('IsAppearanceAllowed', function(source, appearance)
    return validate(source, appearance)
end)

---Applies an appearance to a player from the server (an outfit grant, a
---gamemode forcing a skin). Pushed to the client rather than persisted --
---the caller decides whether it should also be saved.
---@param source Source
---@param appearance table
---@param persist boolean?
---@return boolean success
---@return string? error
exports('SetAppearance', function(source, appearance, persist)
    local ok, reason = validate(source, appearance)

    if not ok then
        return false, reason
    end

    TriggerClientEvent('appearance:client:apply', source, appearance)

    if persist then
        return saveAppearance(source, appearance)
    end

    return true
end)

---Server exports get no implicit source, so this takes only what it needs.
---@param model string
---@return boolean
exports('IsPedAllowed', function(model)
    return pedWhitelist[model] == true
end)
