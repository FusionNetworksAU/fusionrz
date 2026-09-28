---One row, 0.9m apart, centre outwards (slot 1 in the middle). At the podium
---camera's zoom that is ~295px between peds, which the 0.66-scaled name cards
---(~263px) fit under without overlapping.
---@type RankedClientPodiumOffsetConfig[]
local defaultPodiumOffset = {
    {forward = 0.0, right = 0.0, cardRow = 2, uiZ = -0.85},
    {forward = 0.0, right = -0.9, cardRow = 2, uiZ = -0.85},
    {forward = 0.0, right = 0.9, cardRow = 2, uiZ = -0.85},
    {forward = 0.0, right = -1.8, cardRow = 2, uiZ = -0.85},
    {forward = 0.0, right = 1.8, cardRow = 2, uiZ = -0.85},
}

---@type RankedClientConfig
return {
    storePreviewPosition = vector4(-3249.0972, 7420.3379, 984.8470, 239.5870),
    storePreviewCameraOffset = vector3(0.0, 0.0, 0.3),
    previewTimecycleName = 'preview',
    previewTimecyleVars = {
        {'light_dir_col_r', 0.0, 1.000},
        {'light_dir_col_g', 0.0, 1.000},
        {'light_dir_col_b', 0.0, 1.000},
        {'light_dir_mult', 0.0, 0.000},
        {'light_directional_amb_intensity_mult', 0.200, 0.000},
        {'light_directional_amb_bounce_enabled', 0.200, 0.000},
        {'light_natural_amb_down_col_r', 0.541, 1.000},
        {'light_natural_amb_down_col_g', 0.650, 1.000},
        {'light_natural_amb_down_col_b', 1.000, 1.000},
        {'light_natural_amb_down_intensity', 0.000, 0.000},
        {'light_natural_amb_up_col_r', 1.000, 1.000},
        {'light_natural_amb_up_col_g', 0.847, 1.000},
        {'light_natural_amb_up_col_b', 0.459, 1.000},
        {'light_natural_amb_up_intensity', 0.100, 0.000},
        {'light_artificial_int_up_intensity', 0.000, 0.000},
        {'postfx_intensity_bloom', 0.000, 0.000},
        {'artificial_int_ambient_multiplier', -1.000, 0.000}
    },
    previewPedSize = 2.0,
    previewVehicleSize = 4.0,
    podium = {
        position = vector4(224.0433, -3261.7795, 40.4645, 91.4100),
        fov = 23.0,
        distance = 8.1,
        cameraHeight = 0.61,
        cameraPitch = -5.0,
        cameraRight = 0.55,
        weapon = 'WEAPON_CARBINERIFLE',
        backdrop = {
            image = 'images/lobby_background.png',
            behind = 3.0, 
            width = 14.0,
            height = 8.0,
            bottom = -4.0, 
        },
        offsets = {
            ['solo'] = defaultPodiumOffset,
            ['duo'] = defaultPodiumOffset,
            ['trio'] = defaultPodiumOffset,
            ['squad'] = defaultPodiumOffset
        },
    },

    portal = {
        coords = vec3(-6200.4761, -5200.1279, 936.5),
        radius = 2.0,
    }
}
