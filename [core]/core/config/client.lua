return {
    spawnLocation = vec4(284.3753, -1574.6082, 30.5321, 28.3914),

    maxPlayerStats = {
        ['MP0_STAMINA'] = 100,
        ['MP0_LUNG_CAPACITY'] = 100,
        ['MP0_WHEELIE_ABILITY'] = 100,
        ['MP0_FLYING_ABILITY'] = 100,
        ['MP0_SHOOTING_ABILITY'] = GetConvarInt('combat_roll', 135)
    },

    defaultAppearanceConfig = {
        ped = true,
        headBlend = true,
        faceFeatures = true,
        headOverlays = true,
        components = false,
        props = false,
        allowExit = false,
        tattoos = false
    }
}
