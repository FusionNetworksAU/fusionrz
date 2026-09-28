---Hopouts-style free-for-all: scripted damage, hotbar loadout, armour siphon.
---
---The client decides almost everything about how these modes feel; what it
---needs from the server is the loadout metadata (`shared.metadata.rifleClient`
---shape) so the hotbar can bind the right primary and melee.

Gamemodes = Gamemodes or {}
Gamemodes.handlers = Gamemodes.handlers or {}

local core = exports.core

---Armour cap handed to `gamemodes:applyKillSiphon`. hopouts' shared config has
---no armour cap of its own (it defines counts, not ceilings), so this is the
---mode's own number rather than a lookup that would quietly fall back.
local MAX_ARMOR = 100

---@param source Source
---@param def GamemodeDefinition
local function applyLoadout(source, def)
    core:RemoveAllWeapons(source)

    local weapons = { def.primaryName, def.meleeName }

    if def.pistolName then
        weapons[#weapons + 1] = def.pistolName
    end

    for index = 1, #weapons do
        core:GiveWeapon(source, weapons[index], 250)
    end

    core:SetWeaponWhitelist(source, weapons)
end

---The shape `shared.metadata.newClient` expects on the client side.
---@param def GamemodeDefinition
---@return table
local function clientMetadata(def)
    local data = {
        rifleName = def.primaryName,
        primaryName = def.primaryName,
        meleeName = def.meleeName,
    }

    if def.pistolName then
        data.pistolName = def.pistolName
    end

    return data
end

---@type GamemodeHandler
Gamemodes.handlers.hopout_style = {
    style = 'hopout',

    ---@param instance GamemodeInstance
    ---@param source Source
    onEnter = function(instance, source)
        applyLoadout(source, instance.def)

        return clientMetadata(instance.def)
    end,

    ---@param instance GamemodeInstance
    ---@param source Source
    onRespawn = function(instance, source)
        applyLoadout(source, instance.def)
    end,

    ---@param instance GamemodeInstance
    ---@param killer Source?
    onKill = function(instance, killer)
        if not killer then
            return
        end

        -- Reward the kill with armour rather than health, the way hopouts does.
        TriggerClientEvent('gamemodes:applyKillSiphon', killer, MAX_ARMOR)

        local score = instance.scores[killer]

        if score and score.kills >= instance.def.killTarget then
            Gamemodes.endMatch(instance)
        end
    end,

    ---@param instance GamemodeInstance
    ---@param source Source
    ---@return integer value
    ---@return integer maxValue
    getStats = function(instance, source)
        local score = instance.scores[source]

        return score and score.kills or 0, instance.def.killTarget
    end,

    ---@param source Source
    onExit = function(_, source)
        core:ResetWeaponWhitelist(source)
        core:RemoveAllWeapons(source)
    end,
}
