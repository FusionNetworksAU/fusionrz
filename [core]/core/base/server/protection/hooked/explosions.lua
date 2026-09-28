---Explosion types no weapon in data/weapons.lua can produce. Anything on this
---list arriving from a client is a menu, so it is cancelled outright.

---@type table<integer, string>
local blockedTypes = {
    [2] = 'STICKYBOMB',
    [4] = 'ROCKET',
    [5] = 'TANKSHELL',
    [6] = 'HI_OCTANE',
    [7] = 'CAR',
    [8] = 'PLANE',
    [9] = 'PETROL_PUMP',
    [10] = 'BIKE',
    [11] = 'DIR_STEAM',
    [12] = 'DIR_FLAME',
    [13] = 'DIR_WATER_HYDRANT',
    [14] = 'DIR_GAS_CANISTER',
    [15] = 'BOAT',
    [16] = 'SHIP_DESTROY',
    [17] = 'TRUCK',
    [18] = 'BULLET',
    [19] = 'SMOKEGRENADELAUNCHER',
    [21] = 'BZGAS',
    [23] = 'EXTINGUISHER',
    [25] = 'EXP_TAG_TRAIN',
    [26] = 'EXP_TAG_BARREL',
    [27] = 'EXP_TAG_PROPANE',
    [28] = 'EXP_TAG_BLIMP',
    [29] = 'EXP_TAG_DIR_FLAME_EXPLODE',
    [30] = 'EXP_TAG_TANKER',
    [32] = 'EXP_TAG_BLIMP2',
    [33] = 'EXP_TAG_FIREWORK',
    [34] = 'EXP_TAG_SNOWBALL',
    [35] = 'EXP_TAG_PROXMINE',
    [36] = 'EXP_TAG_VALKYRIE_CANNON',
}

AddEventHandler('explosionEvent', function(sender, data)
    local source = tonumber(sender) --[[@as Source]]

    if not source or source == 0 then
        return
    end

    local blocked = blockedTypes[data.explosionType]

    if not blocked then
        return
    end

    CancelEvent()

    Core.flag(source, 'explosion', blocked, 'protection_explosion')
end)
