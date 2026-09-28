if IsDuplicityVersion() then return end

local core = exports.core

---Reading the export at file scope throws if `core` has not started yet in
---this client's resource order, and a throw here aborts the whole file --
---taking the event handlers below with it and leaving PlayerData nil forever
---in the consuming resource. That is what every
---"attempt to index a nil value (global 'PlayerData')" came from.
---@return table
local function readPlayerData()
    local ok, data = pcall(function()
        return core:GetPlayerData()
    end)

    return (ok and type(data) == 'table') and data or {}
end

PlayerData = readPlayerData()

RegisterNetEvent('core:onPlayerLoaded', function()
    PlayerData = readPlayerData()
end)

---@param data table
RegisterNetEvent('core:onCoinsChange', function(data)
    PlayerData.coins = data.newAmount
end)

---@param key string
---@param value any
RegisterNetEvent('core:onSetMetadata', function(key, value)
    -- PlayerData is an empty table when there is no player data available.
    if PlayerData and PlayerData.metadata then
        PlayerData.metadata[key] = value
    end
end)

---@param weaponHash string
---@param ammoCount number
RegisterNetEvent('core:onGiveWeapon', function(weaponHash, ammoCount)
    PlayerData.weapons[weaponHash] = ammoCount
end)

---@param weaponHash string
---@param ammoCount number
RegisterNetEvent('core:onSetWeaponAmmo', function(weaponHash, ammoCount)
    PlayerData.weapons[weaponHash] = ammoCount
end)

---@param weaponHash string
RegisterNetEvent('core:onRemoveWeapon', function(weaponHash)
    PlayerData.weapons[weaponHash] = nil
end)

RegisterNetEvent('core:onRemoveAllWeapons', function()
    PlayerData.weapons = {}
end)
