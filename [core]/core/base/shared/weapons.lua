---@alias WeaponType 'rifle' | 'pistol' | 'smg' | 'shotgun' | 'heavy' | 'melee'

---The spawn name of a weapon ('WEAPON_TMFCOMBATPISTOL'). Skins in the items
---table point at one of these through WeaponItem.baseWeapon.
---@alias WeaponBaseType string

---@class WeaponData
---@field label string
---@field type WeaponType
---@field hash integer
---@field ace? string

---@alias WeaponConfig table<WeaponBaseType, WeaponData>

---@type WeaponConfig
local weapons = require 'data.weapons'

---@type table<integer, WeaponBaseType>
local weaponsByHash = {}

---@type WeaponConfig
local weaponsWithAce = {}

for weaponId, weaponData in pairs(weapons) do
    weaponsByHash[weaponData.hash] = weaponId

    if weaponData.ace then
        weaponsWithAce[weaponId] = weaponData
    end
end

Core.weapons = weapons

---@return WeaponConfig
function Core.getWeapons()
    return weapons
end

---Only the weapons gated behind an ace. base/server/protection/weapons.lua and
---the UI both walk this instead of the full table, since the ungated majority
---never needs a permission check.
---@return WeaponConfig
function Core.getWeaponsWithAce()
    return weaponsWithAce
end

---@param weaponId WeaponBaseType
---@return WeaponData?
function Core.getWeaponData(weaponId)
    return weapons[weaponId]
end

---@param hash integer
---@return WeaponBaseType?
function Core.getWeaponIdByHash(hash)
    return weaponsByHash[hash]
end

---@param weaponId WeaponBaseType
---@return boolean
function Core.isWeapon(weaponId)
    return weapons[weaponId] ~= nil
end

---Resolves whatever the caller has (name or hash) to the canonical spawn name.
---@param weapon WeaponBaseType | integer
---@return WeaponBaseType?
function Core.resolveWeaponId(weapon)
    if type(weapon) == 'number' then
        return weaponsByHash[weapon]
    end

    if type(weapon) ~= 'string' then
        return nil
    end

    local upper = weapon:upper()

    return weapons[upper] and upper or nil
end

return weapons
