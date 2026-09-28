local weaponcosmetics = exports.weaponcosmetics
local shop = exports.shop

---@param data table[]
exports('setOwnedCharms', function(data)
    SendNUIMessage({ action = 'setOwnedCharms', data = data })
end)

---@param data table<string, { id: string, skin: string, offset: { x: number, y: number, z: number }, normal: { x: number, y: number, z: number }? }>
exports('setEquippedCharms', function(data)
    SendNUIMessage({ action = 'setEquippedCharms', data = data })
end)

---@param data { key: string, label: string, image: string }[]
exports('setCosmeticWeapons', function(data)
    SendNUIMessage({ action = 'setCosmeticWeapons', data = data })
end)

---@param data { baseWeaponName: string }
---@param cb function
RegisterNUICallback('previewCosmeticWeapon', function(data, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    cb(weaponcosmetics:previewEquippedWeapon(data.baseWeaponName))
end)

---@param data { baseWeaponName: string, itemId: string }
---@param cb function
RegisterNUICallback('openWeaponPlacement', function(data, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    cb(weaponcosmetics:openPlacement(data.baseWeaponName, data.itemId))
end)

---@param data { nx: number, ny: number, crop: table? }
---@param cb function
RegisterNUICallback('weaponPlacementPointAt', function(data, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local offset, normal = weaponcosmetics:placementPointAt(data.nx, data.ny, data.crop)

    cb({ offset = offset, normal = normal })
end)

---@param x number? screen fraction across, nil hides the handle
---@param y number? screen fraction down
exports('setCharmPoint', function(x, y)
    SendNUIMessage({
        action = 'setCharmPoint',
        data = x and { x = x, y = y } or false,
    })
end)

---@param _ any
---@param cb function
RegisterNUICallback('closeWeaponPlacement', function(_, cb)
    weaponcosmetics:closePlacement()
    cb(true)
end)

---@param packed { x: number, y: number, z: number }?
---@return vector3?
local function toVector3(packed)
    if type(packed) ~= 'table' or type(packed.x) ~= 'number' or type(packed.y) ~= 'number' or type(packed.z) ~= 'number' then
        return nil
    end

    return vec3(packed.x, packed.y, packed.z)
end

---@param data { baseWeaponName: string, charmId: string?, offset: table?, normal: table? }
---@param cb function
RegisterNUICallback('equipWeaponCharm', function(data, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    cb(lib.callback.await('weaponcosmetics:server:equipCharm', false,
        data.baseWeaponName, data.charmId, toVector3(data.offset), toVector3(data.normal)))
end)
