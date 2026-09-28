---Round loadouts.
---
---Which weapons a round gives is a rule, not a choice: config/shared.lua
---lists the pistol-only rounds, and everything else is the full kit. The
---server decides and pushes it, so a client cannot hand itself a rifle on a
---pistol round.

Hopouts = Hopouts or {}

---@param match HopOutMatch
---@return integer[]
local function getPistolRounds(match)
    local config = Hopouts.sharedConfig

    return #match.sides > 2 and config.multiTeamsPistolOnlyRounds or config.pistolOnlyRounds
end

---@param match HopOutMatch
---@param round integer?
---@return boolean
function Hopouts.isPistolRound(match, round)
    round = round or match.round

    local rounds = getPistolRounds(match)

    for index = 1, #rounds do
        if rounds[index] == round then
            return true
        end
    end

    return false
end

---@param match HopOutMatch
---@return table
function Hopouts.buildLoadout(match)
    local config = Hopouts.sharedConfig
    local pistolOnly = Hopouts.isPistolRound(match)

    ---@type { name: string, ammo: integer }[]
    local weapons = {
        { name = config.pistolName, ammo = pistolOnly and 120 or 60 },
        { name = config.meleeName, ammo = 1 },
    }

    if not pistolOnly then
        table.insert(weapons, 1, { name = config.rifleName, ammo = 250 })
    end

    return {
        pistolOnly = pistolOnly,
        weapons = weapons,
        smokes = pistolOnly and 0 or config.smokeGrenadeCount,
        smokeName = config.smokeGrenadeName,
        armour = config.numArmors,
        medkits = config.numMedKits,
    }
end

---Pushed at the start of every round. The client applies it; the server
---keeps the authoritative copy so protection can tell a legitimate weapon
---from one that appeared out of nowhere.
---@param match HopOutMatch
function Hopouts.applyLoadouts(match)
    local loadout = Hopouts.buildLoadout(match)

    match.loadout = loadout

    for playerSource, player in pairs(match.players) do
        if player.connected then
            TriggerClientEvent('hopouts:client:loadout', playerSource, loadout)
        end
    end

    -- Narrow the per-match weapon whitelist to exactly this round's kit, so
    -- core's weaponDamageEvent hook rejects anything else.
    local allowed = {}

    for index = 1, #loadout.weapons do
        allowed[#allowed + 1] = loadout.weapons[index].name
    end

    if loadout.smokes > 0 then
        allowed[#allowed + 1] = loadout.smokeName
    end

    for playerSource in pairs(match.players) do
        exports.core:SetWeaponWhitelist(playerSource, allowed)
    end
end

---@param match HopOutMatch
function Hopouts.clearLoadouts(match)
    for playerSource in pairs(match.players) do
        exports.core:ResetWeaponWhitelist(playerSource)

        TriggerClientEvent('hopouts:client:clearLoadout', playerSource)
    end
end
