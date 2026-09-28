local utils = {}

---@param modelName string
---@return string | false vehicleType
function utils.getVehicleType(modelName)
    if type(modelName) ~= 'string' then
        return false
    end

    if not IsModelInCdimage(modelName) or not IsModelValid(modelName) then
        return false
    end

    local modelHash = lib.requestModel(modelName)
    local entity = CreateVehicle(modelHash, 0, 0, -200, 0, false, false)

    FreezeEntityPosition(entity, true)
    SetEntityInvincible(entity, true)
    SetEntityVisible(entity, false, false)
    SetEntityCompletelyDisableCollision(entity, false, false)
    SetModelAsNoLongerNeeded(modelHash)

    local vehicleType = GetVehicleType(entity)

    SetEntityAsMissionEntity(entity, false, true)
    DeleteEntity(entity)

    return vehicleType
end

return utils