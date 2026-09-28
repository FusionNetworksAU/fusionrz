---Actions a staff member takes on themselves.
---
---Mostly client-side by nature (noclip, nametags, the camera), so the server
---keeps only what must be authoritative: the teleport destinations, the
---routing bucket, and the saved-coords slot that has to survive a respawn.

local core = exports.core
local config = require 'config.client'

---One saved position per staff member, cleared when they drop. Deliberately
---not persisted: it is a scratch slot for the session, not a bookmark.
---@type table<Source, vector4>
local savedCoords = {}

---@param source Source
---@param coords vector3 | vector4
---@return boolean
local function teleportSelf(source, coords)
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

---@return { coords: vector4, label: string }[]
lib.callback.register('admin:server:getTeleportLocations', function(source)
    if not Admin.isStaff(source) then
        return {}
    end

    return config.teleportLocations
end)

---@param index integer
---@return boolean success
---@return string message
lib.callback.register('admin:server:teleportToLocation', function(source, index)
    local allowed, err = Admin.gate(source, 'teleport')

    if not allowed then
        return false, err
    end

    index = tonumber(index) --[[@as integer]]

    local location = index and config.teleportLocations[math.floor(index)]

    if not location then
        return false, locale('no_saved_coords')
    end

    if not teleportSelf(source, location.coords) then
        return false, locale('teleport_busy')
    end

    Admin.log(source, 'teleported to', nil, location.label)

    return true, ('Teleported to %s.'):format(location.label)
end)

---@param coords vector3 | table
---@return boolean success
---@return string message
lib.callback.register('admin:server:teleportToCoords', function(source, coords)
    local allowed, err = Admin.gate(source, 'teleport')

    if not allowed then
        return false, err
    end

    if type(coords) ~= 'table' or type(coords.x) ~= 'number' or type(coords.y) ~= 'number' or type(coords.z) ~= 'number' then
        return false, locale('no_waypoint_set')
    end

    if not teleportSelf(source, coords) then
        return false, locale('teleport_busy')
    end

    return true, locale('teleported_to_player')
end)

---@return boolean success
---@return string message
lib.callback.register('admin:server:saveCoords', function(source)
    if not Admin.isStaff(source) then
        return false, locale('no_perms')
    end

    local ped = GetPlayerPed(source --[[@as string]])

    if ped == 0 then
        return false, locale('teleport_busy')
    end

    local coords = GetEntityCoords(ped)

    savedCoords[source] = vec4(coords.x, coords.y, coords.z, GetEntityHeading(ped))

    return true, locale('coords_copied')
end)

---@return boolean success
---@return string message
lib.callback.register('admin:server:returnToSavedCoords', function(source)
    if not Admin.isStaff(source) then
        return false, locale('no_perms')
    end

    local coords = savedCoords[source]

    if not coords then
        return false, locale('no_saved_coords')
    end

    if not teleportSelf(source, coords) then
        return false, locale('teleport_busy')
    end

    return true, locale('teleported_to_player')
end)

---Back to the lobby bucket, which is also how a staff member gets out of a
---match instance they walked into.
---@return boolean success
lib.callback.register('admin:server:returnToLobby', function(source)
    if not Admin.isStaff(source) then
        return false
    end

    core:SetPlayerBucket(source, 0)
    core:TeleportToSpawn(source)

    return true
end)

AddEventHandler('playerDropped', function()
    savedCoords[source --[[@as Source]]] = nil
end)
