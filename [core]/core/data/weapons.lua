---Every weapon the server knows, one entry each.
---
---Free weapons have no `ace`: anyone can take them from the Weapons tab. A
---shop weapon's `ace` is `weapons.<id in lower case>` -- core builds an item's
---permission as `<category>.<item id>`, so owning the shop item `weapon_rpg`
---(category `weapons`) is exactly what unlocks WEAPON_RPG, and nothing else.
---The shop items themselves are rows in the `items` table (core/shop_weapons.sql).
---
---This list used to carry duplicates (a free and a locked copy of the carbine,
---pump shotgun, combat MG...), where whichever came last silently won, and
---every locked gun shared one ace, so a single purchase would have unlocked
---all of them.

---@param id string
---@return string
local function shopAce(id)
    return 'weapons.' .. id:lower()
end

---@type WeaponConfig
local data = {
    -- --------------------------------------------------------------- free ----
    -- Pistols
    ['WEAPON_PISTOL'] = { label = 'Pistol', type = 'pistol' },
    ['WEAPON_COMBATPISTOL'] = { label = 'Combat Pistol', type = 'pistol' },
    ['WEAPON_APPISTOL'] = { label = 'AP Pistol', type = 'pistol' },
    ['WEAPON_SNSPISTOL'] = { label = 'SNS Pistol', type = 'pistol' },
    ['WEAPON_HEAVYPISTOL'] = { label = 'Heavy Pistol', type = 'pistol' },
    ['WEAPON_CERAMICPISTOL'] = { label = 'Ceramic Pistol', type = 'pistol' },
    ['WEAPON_VINTAGEPISTOL'] = { label = 'Vintage Pistol', type = 'pistol' },
    ['WEAPON_PISTOL50'] = { label = 'Pistol .50', type = 'pistol' },
    ['WEAPON_REVOLVER'] = { label = 'Revolver', type = 'pistol' },
    ['WEAPON_DOUBLEACTION'] = { label = 'Double Action Revolver', type = 'pistol' },
    ['WEAPON_NERF'] = { label = 'Toy Pistol', type = 'pistol' },
    ['WEAPON_BLASTGUN'] = { label = 'Blastgun', type = 'pistol' },

    -- SMGs
    ['WEAPON_MICROSMG'] = { label = 'Micro SMG', type = 'smg' },
    ['WEAPON_MINISMG'] = { label = 'Mini SMG', type = 'smg' },
    ['WEAPON_SMG_MK2'] = { label = 'SMG MK2', type = 'smg' },
    ['WEAPON_COMBATPDW'] = { label = 'Combat PDW', type = 'smg' },

    -- Rifles (the carbine is the hopouts and gamemodes primary)
    ['WEAPON_CARBINERIFLE'] = { label = 'Carbine Rifle', type = 'rifle' },
    ['WEAPON_CARBINERIFLE_MK2'] = { label = 'Carbine Rifle MK2', type = 'rifle' },
    ['WEAPON_ASSAULTRIFLE'] = { label = 'Assault Rifle', type = 'rifle' },
    ['WEAPON_ASSAULTRIFLE_MK2'] = { label = 'Assault Rifle MK2', type = 'rifle' },
    ['WEAPON_SPECIALCARBINE'] = { label = 'Special Carbine', type = 'rifle' },
    ['WEAPON_SPECIALCARBINE_MK2'] = { label = 'Special Carbine MK2', type = 'rifle' },
    ['WEAPON_BULLPUPRIFLE'] = { label = 'Bullpup Rifle', type = 'rifle' },
    ['WEAPON_BULLPUPRIFLE_MK2'] = { label = 'Bullpup Rifle MK2', type = 'rifle' },
    ['WEAPON_COMPACTRIFLE'] = { label = 'Compact Rifle', type = 'rifle' },
    ['WEAPON_TACTICALRIFLE'] = { label = 'Tactical Rifle', type = 'rifle' },
    ['WEAPON_GUSENBERG'] = { label = 'Gusenberg', type = 'rifle' },
    ['WEAPON_MG'] = { label = 'MG', type = 'rifle' },
    ['WEAPON_COMBATMG'] = { label = 'Combat MG', type = 'rifle' },
    ['WEAPON_COMBATMG_MK2'] = { label = 'Combat MG MK2', type = 'rifle' },
    ['WEAPON_MARKSMANRIFLE'] = { label = 'Marksman Rifle', type = 'rifle' },
    ['WEAPON_HEAVYSNIPER'] = { label = 'Heavy Sniper', type = 'rifle' },
    ['WEAPON_MOSIN'] = { label = 'Mosin', type = 'rifle' },

    -- Melee
    ['WEAPON_STONE_HATCHET'] = { label = 'Stone Hatchet', type = 'melee' },

    -- Round kit only (hopouts smoke): never listed, issued by the loadout.
    ['WEAPON_SMOKEGRENADE'] = { label = 'Smoke Grenade', type = 'melee', ace = 'hidden' },

    -- --------------------------------------------------------------- shop ----
    ['WEAPON_MILITARYRIFLE'] = { label = 'Military Rifle', type = 'rifle', ace = shopAce('WEAPON_MILITARYRIFLE') },
    ['WEAPON_PRECISIONRIFLE'] = { label = 'Precision Rifle', type = 'rifle', ace = shopAce('WEAPON_PRECISIONRIFLE') },
    ['WEAPON_MARKSMANRIFLE_MK2'] = { label = 'Marksman Rifle MK2', type = 'rifle', ace = shopAce('WEAPON_MARKSMANRIFLE_MK2') },
    ['WEAPON_SNIPERRIFLE'] = { label = 'Sniper Rifle', type = 'rifle', ace = shopAce('WEAPON_SNIPERRIFLE') },
    ['WEAPON_SMG'] = { label = 'SMG', type = 'smg', ace = shopAce('WEAPON_SMG') },
    ['WEAPON_ASSAULTSMG'] = { label = 'Assault SMG', type = 'smg', ace = shopAce('WEAPON_ASSAULTSMG') },
    ['WEAPON_PISTOL_MK2'] = { label = 'Pistol MK2', type = 'pistol', ace = shopAce('WEAPON_PISTOL_MK2') },
    ['WEAPON_REVOLVER_MK2'] = { label = 'Revolver MK2', type = 'pistol', ace = shopAce('WEAPON_REVOLVER_MK2') },
    ['WEAPON_PUMPSHOTGUN'] = { label = 'Pump Shotgun', type = 'shotgun', ace = shopAce('WEAPON_PUMPSHOTGUN') },
    ['WEAPON_DBSHOTGUN'] = { label = 'Double Barrel Shotgun', type = 'shotgun', ace = shopAce('WEAPON_DBSHOTGUN') },
    ['WEAPON_SAWNOFFSHOTGUN'] = { label = 'Sawed-Off Shotgun', type = 'shotgun', ace = shopAce('WEAPON_SAWNOFFSHOTGUN') },
    ['WEAPON_ASSAULTSHOTGUN'] = { label = 'Assault Shotgun', type = 'shotgun', ace = shopAce('WEAPON_ASSAULTSHOTGUN') },
    ['WEAPON_COMBATSHOTGUN'] = { label = 'Combat Shotgun', type = 'shotgun', ace = shopAce('WEAPON_COMBATSHOTGUN') },
    ['WEAPON_GRENADELAUNCHER'] = { label = 'Grenade Launcher', type = 'heavy', ace = shopAce('WEAPON_GRENADELAUNCHER') },
    ['WEAPON_RPG'] = { label = 'RPG', type = 'heavy', ace = shopAce('WEAPON_RPG') },
    ['WEAPON_MINIGUN'] = { label = 'Minigun', type = 'heavy', ace = shopAce('WEAPON_MINIGUN') },
    ['WEAPON_GRENADE'] = { label = 'Grenade', type = 'melee', ace = shopAce('WEAPON_GRENADE') },
    ['WEAPON_PIPEBOMB'] = { label = 'Pipe Bomb', type = 'melee', ace = shopAce('WEAPON_PIPEBOMB') },
    ['WEAPON_MOLOTOV'] = { label = 'Molotov', type = 'melee', ace = shopAce('WEAPON_MOLOTOV') },
    ['WEAPON_STICKYBOMB'] = { label = 'Sticky Bomb', type = 'melee', ace = shopAce('WEAPON_STICKYBOMB') },
    ['WEAPON_FLARE'] = { label = 'Flare', type = 'melee', ace = shopAce('WEAPON_FLARE') },
}

for weaponId, entry in pairs(data) do
    entry.hash = joaat(weaponId)
end

return data
