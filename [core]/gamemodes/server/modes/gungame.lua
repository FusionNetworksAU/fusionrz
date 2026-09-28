---Gun game: every kill moves you up the weapon ladder, a knife kill knocks the
---victim back down one rung, and the first kill with the final weapon wins.

Gamemodes = Gamemodes or {}
Gamemodes.handlers = Gamemodes.handlers or {}

local core = exports.core

---The ladder, rung 1 upward. Every entry is a weapon that exists in
---`@core.data.weapons`.
local LADDER = {
    'WEAPON_APPISTOL',
    'WEAPON_COMBATPISTOL',
    'WEAPON_PISTOL50',
    'WEAPON_MICROSMG',
    'WEAPON_SMG',
    'WEAPON_COMBATPDW',
    'WEAPON_CARBINERIFLE',
    'WEAPON_SPECIALCARBINE',
    'WEAPON_BULLPUPRIFLE',
    'WEAPON_PUMPSHOTGUN',
    'WEAPON_SNIPERRIFLE',
    -- The catalogue's hatchet, not WEAPON_STONEHATCHET: core resolves every
    -- weapon through @core.data.weapons and silently refuses unknown ids.
    'WEAPON_STONEHATCHET',
}

Gamemodes.gungameLadder = LADDER

---@param source Source
---@param rung integer
local function applyRung(source, rung)
    local weapon = LADDER[rung]

    if not weapon then
        return
    end

    core:RemoveAllWeapons(source)
    core:GiveWeapon(source, weapon, 250)
    core:SetWeaponWhitelist(source, { weapon })
end

---@param instance GamemodeInstance
---@param source Source
---@return integer
local function rungOf(instance, source)
    instance.gungame = instance.gungame or {}
    instance.gungame[source] = instance.gungame[source] or 1

    return instance.gungame[source]
end

---@type GamemodeHandler
Gamemodes.handlers.gungame = {
    style = 'ffa',

    ---@param instance GamemodeInstance
    ---@param source Source
    onEnter = function(instance, source)
        applyRung(source, rungOf(instance, source))

        return nil
    end,

    ---@param instance GamemodeInstance
    ---@param source Source
    onRespawn = function(instance, source)
        applyRung(source, rungOf(instance, source))
    end,

    ---@param instance GamemodeInstance
    ---@param killer Source?
    ---@param victim Source?
    ---@param isMelee boolean?
    onKill = function(instance, killer, victim, isMelee)
        if not killer then
            return
        end

        -- A hatchet kill demotes the victim instead of promoting the killer,
        -- which is the part of gun game that makes the last rung a real fight.
        if isMelee and victim then
            local victimRung = rungOf(instance, victim)

            if victimRung > 1 then
                instance.gungame[victim] = victimRung - 1
            end
        end

        local rung = rungOf(instance, killer)

        if rung >= #LADDER then
            Gamemodes.endMatch(instance)

            return
        end

        instance.gungame[killer] = rung + 1
        applyRung(killer, rung + 1)

        -- The stats bar tracks ladder position here, not raw kills.
        Gamemodes.pushStats(instance, killer)
    end,

    ---@param instance GamemodeInstance
    ---@param source Source
    ---@return integer value
    ---@return integer maxValue
    getStats = function(instance, source)
        return rungOf(instance, source), #LADDER
    end,

    ---@param source Source
    onExit = function(_, source)
        core:ResetWeaponWhitelist(source)
        core:RemoveAllWeapons(source)
    end,
}
