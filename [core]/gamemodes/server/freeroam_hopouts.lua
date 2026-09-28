---Freeroam hopouts: the hopouts loadout handed out inside a freeroam lobby,
---rather than a round-based mode.
---
---The client starts this off the lobby config (`gamemode == 'freeroam_hopouts'`),
---so it stays dormant until the lobby resource is in place. The server half is
---small: hand out the loadout, and own the two world effects that have to be
---created server side so every player sees them.

Gamemodes = Gamemodes or {}

local hopoutsShared = require '@hopouts.config.shared'

local core = exports.core

---@type table<Source, true>
local active = {}

---@param source Source
local function clearLoadout(source)
    if not active[source] then
        return
    end

    active[source] = nil

    core:ResetWeaponWhitelist(source)
    core:RemoveAllWeapons(source)
end

lib.callback.register('gamemodes:server:freeroamHopoutsLoadout', function(source)
    local weapons = {
        hopoutsShared.rifleName,
        hopoutsShared.pistolName,
        hopoutsShared.meleeName,
    }

    core:RemoveAllWeapons(source)

    for index = 1, #weapons do
        core:GiveWeapon(source, weapons[index], 250)
    end

    core:SetWeaponWhitelist(source, weapons)

    active[source] = true

    -- Matches `shared.metadata.newClient`, which is what the hotbar reads.
    return {
        rifleName = hopoutsShared.rifleName,
        primaryName = hopoutsShared.rifleName,
        pistolName = hopoutsShared.pistolName,
        meleeName = hopoutsShared.meleeName,
    }
end)

RegisterNetEvent('gamemodes:server:clearFreeroamHopoutsLoadout', function()
    clearLoadout(source)
end)

---Smoke is created server side so it is not a purely local effect: everyone in
---the lobby needs to be blocked by the same cloud.
RegisterNetEvent('gamemodes:server:createFreeroamHopoutsSmoke', function(coords)
    if type(coords) ~= 'vector3' and type(coords) ~= 'table' then
        return
    end

    local bucket = core:GetPlayerBucket(source)

    for _, target in pairs(core:GetPlayerSources()) do
        if core:GetPlayerBucket(target) == bucket then
            TriggerClientEvent('gamemodes:createFreeroamHopoutsSmoke', target, coords)
        end
    end
end)

RegisterNetEvent('gamemodes:server:repairFreeroamHopoutsVehicle', function(netId)
    if type(netId) ~= 'number' then
        return
    end

    local vehicle = NetworkGetEntityFromNetworkId(netId)

    if not vehicle or not DoesEntityExist(vehicle) then
        return
    end

    -- The owner does the actual repair; the server only decides that it may.
    TriggerClientEvent('gamemodes:repairFreeroamHopoutsVehicle', NetworkGetEntityOwner(vehicle), netId)
end)

AddEventHandler('playerDropped', function()
    active[source] = nil
end)
