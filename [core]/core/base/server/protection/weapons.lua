---Per-player weapon whitelist.
---
---A gamemode narrows what a player may hold for the duration of a match
---(data/locations.lua carries allowedWeapons per map). The whitelist lives
---server-side so the hooked weaponDamageEvent in protection/hooked can reject
---a hit from a weapon the player was never allowed to be holding.

---@type table<Source, table<string, true>> nil entry = every weapon allowed
local whitelists = {}

---@param source Source
---@param weaponIds string[]
function Core.setWeaponWhitelist(source, weaponIds)
    if type(weaponIds) ~= 'table' then
        return
    end

    ---@type table<string, true>
    local allowed = {}

    for index = 1, #weaponIds do
        local weaponId = Core.resolveWeaponId(weaponIds[index])

        if weaponId then
            allowed[weaponId] = true
        end
    end

    whitelists[source] = allowed

    TriggerClientEvent('core:setWeaponWhitelist', source, weaponIds)
end

---@param source Source
function Core.resetWeaponWhitelist(source)
    whitelists[source] = nil

    TriggerClientEvent('core:resetWeaponWhitelist', source)
end

---@param source Source
---@param weapon string | integer
---@return boolean
function Core.isWeaponAllowed(source, weapon)
    local allowed = whitelists[source]

    if not allowed then
        return true
    end

    local weaponId = Core.resolveWeaponId(weapon)

    if not weaponId then
        return false
    end

    return allowed[weaponId] == true
end

---Ace-gated weapons are a separate question from the per-match whitelist: the
---whitelist says what this map permits, the ace says whether this player has
---been granted the weapon at all (through a purchase, which lands in their
---inventory, or through a plain server ace).
---@param source Source
---@param weapon string | integer
---@return boolean
function Core.hasWeaponEntitlement(source, weapon)
    local weaponId = Core.resolveWeaponId(weapon)

    if not weaponId then
        return false
    end

    local weaponData = Core.getWeaponData(weaponId)

    if not weaponData or not weaponData.ace then
        return true
    end

    -- A match whitelist is only ever set by the server when it hands out a
    -- loadout, so a weapon on it was issued rather than bought. Without this a
    -- gamemode's ace-gated rifle had every hit cancelled and struck against
    -- the shooter as a cheat.
    local allowed = whitelists[source]

    if allowed and allowed[weaponId] then
        return true
    end

    if IsPlayerAceAllowed(source --[[@as string]], weaponData.ace) then
        return true
    end

    local player = Core.getPlayer(source)
    local itemId = player and Core.getItemIdByAce(weaponData.ace)

    return itemId ~= nil and Core.ownsItem(player, itemId)
end

AddEventHandler('playerDropped', function()
    whitelists[source --[[@as Source]]] = nil
end)

exports('SetWeaponWhitelist', Core.setWeaponWhitelist)
exports('ResetWeaponWhitelist', Core.resetWeaponWhitelist)
exports('IsWeaponAllowed', Core.isWeaponAllowed)
exports('HasWeaponEntitlement', Core.hasWeaponEntitlement)
