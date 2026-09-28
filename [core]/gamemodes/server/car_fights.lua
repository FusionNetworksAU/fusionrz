---Car fights: every player gets their own vehicle, spawned server side so the
---net id is valid for everyone before the client is told to get in.

Gamemodes = Gamemodes or {}

local VEHICLE_MODEL = 'issi2'

---@type table<Source, integer> source -> vehicle entity
local vehicles = {}

---@param source Source
local function removeVehicle(source)
    local entity = vehicles[source]

    vehicles[source] = nil

    if entity and DoesEntityExist(entity) then
        DeleteEntity(entity)
    end

    TriggerClientEvent('gamemodes:carFights:vehicleRemoved', source)
end

Gamemodes.removeCarFightsVehicle = removeVehicle

---@param source Source
---@param spawn vector4
---@return integer? netId
function Gamemodes.spawnCarFightsVehicle(source, spawn)
    removeVehicle(source)

    -- Let the client settle the ped at the spawn first; CreateVehicle needs a
    -- populated area or the vehicle falls through the map on some arenas.
    TriggerClientEvent('gamemodes:carFights:prepareSpawn', source, spawn)

    local vehicle = CreateVehicle(joaat(VEHICLE_MODEL), spawn.x, spawn.y, spawn.z, spawn.w, true, true)

    if not vehicle or vehicle == 0 then
        return nil
    end

    local timeout = GetGameTimer() + 5000

    while not DoesEntityExist(vehicle) and GetGameTimer() < timeout do
        Wait(0)
    end

    if not DoesEntityExist(vehicle) then
        return nil
    end

    vehicles[source] = vehicle

    local netId = NetworkGetNetworkIdFromEntity(vehicle)

    TriggerClientEvent('gamemodes:carFights:enterVehicle', source, netId)

    return netId
end

---@param source Source
function Gamemodes.clearCarFights(source)
    removeVehicle(source)
end

AddEventHandler('playerDropped', function()
    removeVehicle(source)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    for playerSource in pairs(vehicles) do
        removeVehicle(playerSource)
    end
end)
