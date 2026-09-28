---Plain free-for-all: fixed loadout, first to the kill target wins.
---
---Loaded before `server/modes/init.lua` (see fxmanifest order), so this file
---only registers its handler; the registry that consumes it is built there.

Gamemodes = Gamemodes or {}
Gamemodes.handlers = Gamemodes.handlers or {}

local core = exports.core

---@param source Source
---@param weapons string[]
local function applyLoadout(source, weapons)
    core:RemoveAllWeapons(source)

    for index = 1, #weapons do
        core:GiveWeapon(source, weapons[index], 250)
    end

    -- Keep players honest: the whitelist is what stops someone pulling a
    -- rifle into a pistol lobby from another resource.
    core:SetWeaponWhitelist(source, weapons)
end

---@type GamemodeHandler
Gamemodes.handlers.ffa = {
    style = 'ffa',

    ---@param instance GamemodeInstance
    ---@param source Source
    onEnter = function(instance, source)
        applyLoadout(source, instance.def.weapons)

        return nil -- no hopouts-style client metadata for plain FFA
    end,

    ---@param instance GamemodeInstance
    ---@param source Source
    onRespawn = function(instance, source)
        applyLoadout(source, instance.def.weapons)
    end,

    ---@param instance GamemodeInstance
    ---@param killer Source?
    onKill = function(instance, killer)
        if not killer then
            return
        end

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
