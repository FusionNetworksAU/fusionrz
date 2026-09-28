local core = exports.core

local AMMO = 500

---@param source number
---@param name any
---@return string? weaponId
local function resolve(source, name)
    if type(name) ~= 'string' or #name > 64 then
        return nil
    end

    local weaponId = name:upper()

    if not core:GetWeaponDataById(weaponId) then
        return nil
    end

    if not core:IsWeaponAllowed(source, weaponId) then
        return nil
    end

    if not core:HasWeaponEntitlement(source, weaponId) then
        return nil
    end

    return weaponId
end

RegisterNetEvent('uis:server:spawnGlobalWeapon', function(name)
    local source = source --[[@as number]]
    local weaponId = resolve(source, name)

    if weaponId then
        core:GiveWeapon(source, weaponId, AMMO)
    end
end)

RegisterNetEvent('uis:server:removeGlobalWeapon', function(name)
    local source = source --[[@as number]]

    if type(name) == 'string' and #name <= 64 then
        core:RemoveWeapon(source, name:upper())
    end
end)

RegisterNetEvent('uis:server:removeAllGlobalWeapons', function()
    core:RemoveAllWeapons(source)
end)
