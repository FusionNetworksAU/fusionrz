local locations = require 'data.locations'

---@type table<Source, string> source -> location key
local locationBySource = {}

---@type table<string, integer> location key -> occupancy
local countsByLocation = {}

---@type table<string, integer> gamemode portal key -> occupancy
local portalCounts = {}

---@param key string?
---@return boolean
local function isKnownLocation(key)
    return type(key) == 'string' and locations[key] ~= nil
end

---@param key string
---@param delta integer
local function adjustCount(key, delta)
    local updated = (countsByLocation[key] or 0) + delta

    countsByLocation[key] = updated > 0 and updated or nil
end

---@param source Source
---@param key string?
function Core.setPlayerLocation(source, key)
    local previous = locationBySource[source]

    if previous == key then
        return
    end

    if previous then
        adjustCount(previous, -1)
    end

    if key then
        adjustCount(key, 1)
    end

    locationBySource[source] = key

    Core.invalidateTopic('teleportCounts')

    TriggerEvent('core:server:onLocationChanged', source, key, previous)
end

---@param source Source
---@return string?
function Core.getPlayerLocation(source)
    return locationBySource[source]
end

---@return table<string, integer>
function Core.getTeleportCounts()
    return countsByLocation
end

---@return table<string, integer>
function Core.getPortalCounts()
    return portalCounts
end

---@param key string
---@param count integer
function Core.setPortalCount(key, count)
    if type(key) ~= 'string' then
        return
    end

    portalCounts[key] = count > 0 and count or nil

    Core.invalidateTopic('gamemodePortalCounts')
end

---@param source Source
---@param coords vector3 | vector4
function Core.teleportPlayer(source, coords)
    local ped = GetPlayerPed(source --[[@as string]])

    if ped == 0 then
        return false
    end

    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)

    if coords.w then
        SetEntityHeading(ped, coords.w)
    end

    return true
end

---@param source Source
function Core.teleportToSpawn(source)
    Core.setPlayerLocation(source, 'spawn')

    TriggerClientEvent('core:client:teleportToSpawn', source)
end

RegisterNetEvent('core:server:setLocation', function(key)
    local source = source --[[@as Source]]

    if not Core.getPlayer(source) then
        return
    end

    if key ~= nil and not isKnownLocation(key) then
        return
    end

    Core.setPlayerLocation(source, key)
end)

AddEventHandler('core:server:onPlayerDropped', function(source)
    Core.setPlayerLocation(source, nil)

    locationBySource[source] = nil
end)

Core.onReady(function()
    Core.registerTopic('teleportCounts', {
        event = 'core:client:teleportCounts',
        build = Core.getTeleportCounts,
    })

    Core.registerTopic('gamemodePortalCounts', {
        event = 'core:client:gamemodePortalCounts',
        build = Core.getPortalCounts,
    })
end)

exports('TeleportPlayer', Core.teleportPlayer)
exports('TeleportToSpawn', Core.teleportToSpawn)
exports('GetTeleportCounts', Core.getTeleportCounts)
exports('SetPortalCount', Core.setPortalCount)
exports('GetPlayerLocation', Core.getPlayerLocation)
