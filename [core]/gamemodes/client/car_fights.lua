local hopoutsClientConfig = require '@hopouts.config.client'

local shop = exports.shop

-- Last plate state applied to the local vehicle, so the plate export only runs when something changed.
local appliedPlateVehicle = 0
local appliedPlateText = nil
local appliedPlateIndex = -1
local isPlateDirty = true

-- Plate purchases and style equips change metadata.
RegisterNetEvent('core:onSetMetadata', function()
    isPlateDirty = true
end)

local ISSI_MODEL = `fnrz_issi7`
local VEHICLE_SPAWNCODE = 'fnrz_issi7'

local active = false
local currentVehicle = 0
local vehicleLivery
local pendingVehicleNetId = nil

---@param vehicle integer
local function initIssiVehicle(vehicle)
    SetVehicleModKit(vehicle, 0)
    SetVehicleMod(vehicle, 11, 2, false)
    SetVehicleMod(vehicle, 13, 2, false)
    SetVehicleMod(vehicle, 12, 2, false)
    SetVehicleMod(vehicle, 15, 3, false)
    ToggleVehicleMod(vehicle, 18, true)

    for extraId = 1, 13 do
        if DoesExtraExist(vehicle, extraId) and IsVehicleExtraTurnedOn(vehicle, extraId) then
            SetVehicleExtra(vehicle, extraId, true)
        end
    end

    SetVehicleRadioEnabled(vehicle, false)
    SetVehRadioStation(vehicle, 'OFF')
    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleDoorsLocked(vehicle, 4)

    local vehicleMods = hopoutsClientConfig.vehicleMods[ISSI_MODEL]
    if vehicleMods and vehicleMods.enabledExtras then
        for _, extraId in pairs(vehicleMods.enabledExtras) do
            SetVehicleExtra(vehicle, extraId, false)
        end
    end
end

---@param vehicle integer
local function applyVehicleLivery(vehicle)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= cache.ped then
        return
    end

    if NetworkHasControlOfEntity(vehicle) then
        local plateText = GetVehicleNumberPlateText(vehicle)
        local plateIndex = GetVehicleNumberPlateTextIndex(vehicle)

        if isPlateDirty or vehicle ~= appliedPlateVehicle or plateText ~= appliedPlateText or plateIndex ~= appliedPlateIndex then
            shop:ApplySelectedVehiclePlate(vehicle)

            appliedPlateVehicle = vehicle
            appliedPlateText = GetVehicleNumberPlateText(vehicle)
            appliedPlateIndex = GetVehicleNumberPlateTextIndex(vehicle)
            isPlateDirty = false
        end
    end

    if not vehicleLivery then
        return
    end

    local modIndex = GetVehicleMod(vehicle, 48)

    if not vehicleLivery.modShopLabel or GetModTextLabel(vehicle, 48, modIndex) ~= vehicleLivery.modShopLabel then
        shop:ApplySelectedVehicleSkin(vehicle, vehicleLivery.spawncode)
    end
end

---@param vehicle integer
local function enforceDriverOnly(vehicle)
    if vehicle == 0 then
        return
    end

    local maxPassengers = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle)) - 1

    for seat = 0, maxPassengers do
        local occupant = GetPedInVehicleSeat(vehicle, seat)

        if occupant ~= 0 and occupant ~= cache.ped then
            TaskLeaveVehicle(occupant, vehicle, 4160)
        end
    end
end

local function refreshVehicleLiveryData()
    vehicleLivery = {
        modShopLabel = shop:GetSelectedLivery(VEHICLE_SPAWNCODE),
        spawncode = VEHICLE_SPAWNCODE,
    }
end

---@param netId integer
local function warpIntoVehicle(netId)
    CreateThread(function()
        local success = lib.waitFor(function()
            if NetworkDoesNetworkIdExist(netId) and NetworkDoesEntityExistWithNetworkId(netId) then
                return true
            end
        end, 'car fights vehicle', 10000)

        if not success then
            return
        end

        local vehicle = NetworkGetEntityFromNetworkId(netId)
        if vehicle == 0 or not DoesEntityExist(vehicle) then
            return
        end

        currentVehicle = vehicle
        initIssiVehicle(vehicle)
        applyVehicleLivery(vehicle)

        for _ = 1, 25 do
            if cache.vehicle == vehicle then
                break
            end

            SetPedIntoVehicle(cache.ped, vehicle, -1)
            Wait(50)
        end

        if cache.vehicle == vehicle then
            TriggerEvent('gamemodes:carFights:vehicleReady')
        end
    end)
end

local function startVehicleThread()
    CreateThread(function()
        while active do
            DisableControlAction(0, 0, true)
            DisableControlAction(0, 23, true)
            DisableControlAction(0, 75, true)
            DisableControlAction(0, 26, true)

            if currentVehicle ~= 0 and DoesEntityExist(currentVehicle) then
                SetVehicleDoorsLocked(currentVehicle, 4)
                enforceDriverOnly(currentVehicle)

                if cache.vehicle == currentVehicle then
                    SetFollowVehicleCamViewMode(4)
                    applyVehicleLivery(currentVehicle)
                elseif cache.vehicle == 0 then
                    SetPedIntoVehicle(cache.ped, currentVehicle, -1)
                end
            elseif cache.vehicle then
                currentVehicle = cache.vehicle
                SetFollowVehicleCamViewMode(4)
                applyVehicleLivery(currentVehicle)
            else
                SetFollowPedCamViewMode(4)
            end

            Wait(0)
        end
    end)
end

RegisterNetEvent('gamemodes:carFights:prepareSpawn', function(spawnCoords)
    if not spawnCoords then
        return
    end

    FreezeEntityPosition(cache.ped, false)
    ClearFocus()
    SetEntityCoords(cache.ped, spawnCoords.x, spawnCoords.y, spawnCoords.z, false, false, false, false)
    SetEntityHeading(cache.ped, spawnCoords.w)
end)

RegisterNetEvent('gamemodes:carFights:enterVehicle', function(netId)
    if type(netId) ~= 'number' then
        return
    end

    if active then
        warpIntoVehicle(netId)
    else
        pendingVehicleNetId = netId
    end
end)

RegisterNetEvent('gamemodes:carFights:vehicleRemoved', function()
    currentVehicle = 0
end)

---@param netId? integer
local function start(netId)
    if active then
        if netId then
            warpIntoVehicle(netId)
        end
        return
    end

    active = true
    refreshVehicleLiveryData()
    startVehicleThread()

    local vehicleNetId = netId or pendingVehicleNetId
    pendingVehicleNetId = nil

    if vehicleNetId then
        warpIntoVehicle(vehicleNetId)
    end
end

---@param netId integer
local function enterVehicle(netId)
    if active then
        warpIntoVehicle(netId)
    else
        pendingVehicleNetId = netId
    end
end

local function resetToThirdPerson()
    SetFollowPedCamViewMode(0)
    SetFollowVehicleCamViewMode(0)
end

local function stop()
    active = false
    currentVehicle = 0
    pendingVehicleNetId = nil

    resetToThirdPerson()

    CreateThread(function()
        for _ = 1, 60 do
            if active then
                return
            end

            resetToThirdPerson()
            Wait(0)
        end
    end)
end

return {
    start = start,
    stop = stop,
    enterVehicle = enterVehicle,
    resetToThirdPerson = resetToThirdPerson,
}
