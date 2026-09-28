---@type HopOutClientConfig
return {
    timecycleEndDurationMsec = 1000,
    healthPerMedkit = 100,
    medKitTimeMsec = 25000,
    bluntTimeMsec = 3000,
    armorTimeMsec = 5000,
    switchSeatTimeMsec = 2000,
    numArmorItems = 5,
    numMedKitItems = 15,
    numRepairKits = 1,
    numJoints = 10,
    vehicleMods = {
        [`adder`] = {
            enabledExtras = {1},
        },
    },
    pullOutGunTimeMsec = 1000,
    noFistLockOnTimeMsec = 1000,
    warsRadio = {
        dict = 'anim@male@holding_radio',
        clip = 'holding_radio_clip',
    },
    warsOxySpeedMsec = 5000,
    warsOxyCount = 6,
    pingTextureDict = 'hopout_pings',
    damageIncreases = {
        {timeLeft = 1000000, health = 2},
        {timeLeft = 240000, health = 5},
        {timeLeft = 180000, health = 8},
        {timeLeft = 120000, health = 9},
        {timeLeft = 60000, health = 10},
        {timeLeft = 0, health = 12},
    },
    facechecksDamageIncreases = {
        {timeLeft = 1000000, health = 2},
        {timeLeft = 142000, health = 5},
        {timeLeft = 106000, health = 8},
        {timeLeft = 71000, health = 9},
        {timeLeft = 35000, health = 10},
        {timeLeft = 0, health = 12},
    },
    repairKitDurationMsec = 10000,
    maxRepairDistance = 5.0,
    switchSideStartAngle = 60.0,
    switchSideTotalAngle = 60.0,
    zoneMaxTimecycleStrength = 0.65,
    damageSyncFrequencyMsec = 200,
    maxRagdollTimeMsec = 1000,
    zoneFirstShownDelayMsec = 10000,
    facechecksZoneFirstShownDelayMsec = 6000,
    useVehicleCollisionDisabling = true,
    freecamKeys = {
        0x31, -- 1
        0x32, -- 2
        0x33, -- 3
        0x34, -- 4
        0x35, -- 5,
        0x36, -- 6
        0x37, -- 7
        0x38, -- 8
        0x39, -- 9
        0x30, -- 0
    },
    freecamTeamOrdering = {
        'Red',
        'Blue',
    },
    winnerPreviewOffsets = {
        {pedOffset = vector3(0.0, 0.0, 0.0), cardHeight = -0.54},
        {pedOffset = vector3(0.75, -1.0, 0.0), cardHeight = -0.9},
        {pedOffset = vector3(-0.75, -1.0, 0.0), cardHeight = -0.9},
        {pedOffset = vector3(1.4, -0.5, 0.0), cardHeight = -0.75},
        {pedOffset = vector3(-1.4, -0.5, 0.0), cardHeight = -0.75},
    },
    winnerPreviewCamera = {
        fov = 40.0,
        distance = 3.0,
        height = 1.15,
        pointHeight = 1.0,
    },
}