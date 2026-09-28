---weaponDamageEvent is the client telling the server "I hit that". Cancelling
---it is what stops damage from a weapon the player is not entitled to, and
---from damage values no legitimate weapon produces.

local MAX_PLAUSIBLE_DAMAGE = GetConvarInt('core:maxWeaponDamage', 500)

AddEventHandler('weaponDamageEvent', function(sender, data)
    local source = tonumber(sender) --[[@as Source]]

    if not Core.getPlayer(source) then
        return CancelEvent()
    end

    local weaponId = Core.getWeaponIdByHash(data.weaponType)

    -- An unknown hash is not automatically an attack: vehicle collisions and
    -- fall damage both arrive here with hashes that are not in data/weapons.
    -- Only the ones we do recognise get judged.
    if weaponId then
        if not Core.isWeaponAllowed(source, weaponId) then
            CancelEvent()

            return Core.flag(source, 'weapon-whitelist', weaponId, 'protection_weapon')
        end

        if not Core.hasWeaponEntitlement(source, weaponId) then
            CancelEvent()

            return Core.flag(source, 'weapon-entitlement', weaponId, 'protection_weapon')
        end
    end

    if data.weaponDamage and data.weaponDamage > MAX_PLAUSIBLE_DAMAGE then
        CancelEvent()

        return Core.flag(source, 'weapon-damage', ('%s dealt %s'):format(weaponId or data.weaponType, data.weaponDamage), 'protection_weapon')
    end
end)
