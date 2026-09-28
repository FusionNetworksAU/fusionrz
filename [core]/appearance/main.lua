local core = exports.core
local ui = exports.ui

local constants = require 'game.constants'
local clientConfig = require 'config.client'
local sharedConfig = require 'config.shared'
local tattooData = require 'data.tattoos'
local allowedPeds = require 'data.peds'

local FREEMODE_MALE = `mp_m_freemode_01`
local FREEMODE_FEMALE = `mp_f_freemode_01`

---@type table?
local working

---The appearance the editor opened with, so a cancel can put it back.
---@type table?
local original

local cam
local menuOpen = false

---True from a first join until the first save: the creator cannot be closed
---without saving, so nobody ends up with an unsaved default character.
local creatingCharacter = false

local FIRST_CHARACTER_CONFIG = {
    ped = true,
    headBlend = true,
    faceFeatures = true,
    headOverlays = true,
    components = true,
    props = true,
    tattoos = false,
    allowExit = false,
}

-- ------------------------------------------------------------------ read ----

---@param ped integer
---@return string
local function getPedModelName(ped)
    local model = GetEntityModel(ped)

    if model == FREEMODE_MALE then
        return 'mp_m_freemode_01'
    end

    if model == FREEMODE_FEMALE then
        return 'mp_f_freemode_01'
    end

    for index = 1, #allowedPeds do
        if joaat(allowedPeds[index]) == model then
            return allowedPeds[index]
        end
    end

    return 'mp_m_freemode_01'
end

---@param ped integer
---@return table[]
local function readComponents(ped)
    local components = {}

    for index = 1, #constants.pedComponentIds do
        local id = constants.pedComponentIds[index]

        components[#components + 1] = {
            component_id = id,
            drawable = GetPedDrawableVariation(ped, id),
            texture = GetPedTextureVariation(ped, id),
        }
    end

    return components
end

---@param ped integer
---@return table[]
local function readProps(ped)
    local props = {}

    for index = 1, #constants.pedPropsIds do
        local id = constants.pedPropsIds[index]

        props[#props + 1] = {
            prop_id = id,
            drawable = GetPedPropIndex(ped, id),
            texture = GetPedPropTextureIndex(ped, id),
        }
    end

    return props
end

---Inheritance a fresh character starts with: parents 0 (Benjamin) and 21
---(Hannah), leaning towards the parent that matches the ped's sex.
---@param model string
---@return table
local function defaultHeadBlend(model)
    local female = model == 'mp_f_freemode_01'

    return {
        shapeFirst = 0,
        shapeSecond = 21,
        shapeThird = 0,
        skinFirst = 0,
        skinSecond = 21,
        skinThird = 0,
        shapeMix = female and 0.8 or 0.2,
        skinMix = 0.5,
        thirdMix = 0.0,
    }
end

---The last head blend written to the ped. GET_PED_HEAD_BLEND_DATA fills a
---struct through a pointer, which Lua cannot read, so it came back as nils
---and every open of the editor reset the parents to 0. Tracked instead.
---@type table?
local appliedHeadBlend

---@param ped integer
---@return table
local function readHeadBlend(ped)
    local blend = appliedHeadBlend or defaultHeadBlend(getPedModelName(ped))
    local copy = {}

    for key, value in pairs(blend) do
        copy[key] = value
    end

    return copy
end

---@param ped integer
---@return table
local function readFaceFeatures(ped)
    local features = {}

    for index = 1, #constants.faceFeatures do
        features[constants.faceFeatures[index]] = GetPedFaceFeature(ped, index - 1)
    end

    return features
end

---@param ped integer
---@return table
local function readHeadOverlays(ped)
    local overlays = {}

    for index = 1, #constants.headOverlays do
        local name = constants.headOverlays[index]
        local _, overlayValue, colourType, firstColour, secondColour, opacity = GetPedHeadOverlayData(ped, index - 1)

        overlays[name] = {
            style = overlayValue == 255 and 0 or overlayValue,
            opacity = opacity or 0.0,
            color = firstColour or 0,
            secondColor = secondColour or 0,
            colorType = colourType,
        }
    end

    return overlays
end

---@param ped integer
---@return table
local function readHair(ped)
    return {
        style = GetPedDrawableVariation(ped, 2),
        color = GetPedHairColor(ped),
        highlight = GetPedHairHighlightColor(ped),
        texture = GetPedTextureVariation(ped, 2),
    }
end

---@type table[]
local appliedTattoos = {}

---@param ped integer
---@return table
local function readAppearance(ped)
    return {
        model = getPedModelName(ped),
        headBlend = readHeadBlend(ped),
        faceFeatures = readFaceFeatures(ped),
        headOverlays = readHeadOverlays(ped),
        hair = readHair(ped),
        eyeColor = GetPedEyeColor(ped),
        components = readComponents(ped),
        props = readProps(ped),
        tattoos = appliedTattoos,
    }
end

-- ----------------------------------------------------------------- write ----

---@param ped integer
---@param components table[]?
local function applyComponents(ped, components)
    for index = 1, #(components or {}) do
        local component = components[index]

        SetPedComponentVariation(ped, component.component_id, component.drawable, component.texture, 0)
    end
end

---@param ped integer
---@param props table[]?
local function applyProps(ped, props)
    for index = 1, #(props or {}) do
        local prop = props[index]

        if prop.drawable == -1 then
            ClearPedProp(ped, prop.prop_id)
        else
            SetPedPropIndex(ped, prop.prop_id, prop.drawable, prop.texture, true)
        end
    end
end

---@param ped integer
---@param headBlend table?
local function applyHeadBlend(ped, headBlend)
    if not headBlend then
        return
    end

    -- The menu may send only the slider that moved; the rest comes from what
    -- is already on the ped.
    if ped == cache.ped and appliedHeadBlend then
        for key, value in pairs(appliedHeadBlend) do
            if headBlend[key] == nil then
                headBlend[key] = value
            end
        end
    end

    if ped == cache.ped then
        appliedHeadBlend = {
            shapeFirst = headBlend.shapeFirst or 0,
            shapeSecond = headBlend.shapeSecond or 0,
            shapeThird = headBlend.shapeThird or 0,
            skinFirst = headBlend.skinFirst or 0,
            skinSecond = headBlend.skinSecond or 0,
            skinThird = headBlend.skinThird or 0,
            shapeMix = (headBlend.shapeMix or 0.0) + 0.0,
            skinMix = (headBlend.skinMix or 0.0) + 0.0,
            thirdMix = (headBlend.thirdMix or 0.0) + 0.0,
        }
    end

    SetPedHeadBlendData(ped,
        headBlend.shapeFirst or 0, headBlend.shapeSecond or 0, headBlend.shapeThird or 0,
        headBlend.skinFirst or 0, headBlend.skinSecond or 0, headBlend.skinThird or 0,
        (headBlend.shapeMix or 0.0) + 0.0, (headBlend.skinMix or 0.0) + 0.0, (headBlend.thirdMix or 0.0) + 0.0,
        false)
end

---@param ped integer
---@param features table?
local function applyFaceFeatures(ped, features)
    if not features then
        return
    end

    for index = 1, #constants.faceFeatures do
        SetPedFaceFeature(ped, index - 1, (tonumber(features[constants.faceFeatures[index]]) or 0.0) + 0.0)
    end
end

local OVERLAY_COLOR_TYPES = {
    beard = 1, eyebrows = 1, chestHair = 1,
    makeUp = 2, blush = 2, lipstick = 2,
}

---@param ped integer
---@param overlays table?
local function applyHeadOverlays(ped, overlays)
    if not overlays then
        return
    end

    for index = 1, #constants.headOverlays do
        local name = constants.headOverlays[index]
        local overlay = overlays[name]

        if overlay then
            -- Style 0 is a real style (the first eyebrows, the first beard);
            -- the menu hides an overlay with opacity 0, not with style 0.
            -- Mapping 0 to 255 ("none") wiped eyebrows on every overlay edit.
            local style = tonumber(overlay.style) or 0
            local opacity = (tonumber(overlay.opacity) or 0.0) + 0.0

            SetPedHeadOverlay(ped, index - 1, opacity <= 0.0 and 255 or style, opacity)

            -- 1 = hair palette, 2 = makeup palette. Fixed per overlay: the
            -- colorType read back from the ped is 0 until one is set, which
            -- meant beard/eyebrow colour never applied on a fresh character.
            local colorType = OVERLAY_COLOR_TYPES[name]

            if colorType then
                SetPedHeadOverlayColor(ped, index - 1, colorType, overlay.color or 0, overlay.secondColor or overlay.color or 0)
            end
        end
    end
end

---@param ped integer
---@param hair table?
local function applyHair(ped, hair)
    if not hair then
        return
    end

    SetPedComponentVariation(ped, 2, hair.style or 0, hair.texture or 0, 0)
    SetPedHairColor(ped, hair.color or 0, hair.highlight or 0)

    -- The fuzz/stubble overlay that goes with each hairstyle. Without it a
    -- shaved style renders as a bald head with a hard edge.
    local sex = GetEntityModel(ped) == FREEMODE_FEMALE and 'female' or 'male'
    local decoration = constants.hairDecorations[sex] and constants.hairDecorations[sex][hair.style or 0]

    ClearPedDecorations(ped)

    if decoration then
        AddPedDecorationFromHashes(ped, decoration[1], decoration[2])
    end

    for index = 1, #appliedTattoos do
        local tattoo = appliedTattoos[index]

        AddPedDecorationFromHashes(ped, joaat(tattoo.collection), joaat(tattoo.hash))
    end
end

---@param model string
---@return boolean
local function applyModel(model)
    local hash = joaat(model)

    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        return false
    end

    lib.requestModel(hash, 10000)

    SetPlayerModel(cache.playerId, hash)
    SetModelAsNoLongerNeeded(hash)

    -- cache.ped is stale for a frame after a model swap, and every write
    -- below would land on the ped that no longer exists.
    Wait(0)

    -- ox_lib refreshes cache.ped on its own timer, so right after the swap it
    -- still names the deleted ped and everything applyAppearance wrote next
    -- went nowhere. This resource's cache only; core's onCache still fires.
    local ped = PlayerPedId()

    cache.ped = ped

    SetPedDefaultComponentVariation(ped)

    -- A freemode ped with no head blend has no face to edit: the
    -- inheritance and face sliders only take effect once one is set.
    appliedHeadBlend = nil

    if hash == FREEMODE_MALE or hash == FREEMODE_FEMALE then
        applyHeadBlend(ped, defaultHeadBlend(model))
        SetPedHeadOverlay(ped, 2, 0, 1.0) -- eyebrows
        SetPedHeadOverlayColor(ped, 2, 1, 0, 0)
    end

    return true
end

---@param appearance table
local function applyAppearance(appearance)
    if not appearance then
        return
    end

    if appearance.model and appearance.model ~= getPedModelName(cache.ped) then
        applyModel(appearance.model)
    end

    local ped = cache.ped

    applyHeadBlend(ped, appearance.headBlend)
    applyFaceFeatures(ped, appearance.faceFeatures)
    applyHeadOverlays(ped, appearance.headOverlays)
    applyComponents(ped, appearance.components)
    applyProps(ped, appearance.props)

    if appearance.eyeColor then
        SetPedEyeColor(ped, appearance.eyeColor)
    end

    appliedTattoos = appearance.tattoos or {}

    applyHair(ped, appearance.hair)
end

-- ---------------------------------------------------------------- camera ----

---@param key string
local function setCamera(key)
    local preset = constants.cameras[key] or constants.cameras.default
    local offset = constants.offsets[key] or constants.offsets.default
    local ped = cache.ped
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    if not cam then
        cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 50.0, false, 0)

        SetCamActive(cam, true)
        RenderScriptCams(true, true, 500, true, true)
    end

    local forward = preset[1]
    local point = preset[2]
    local rad = math.rad(heading)

    -- The preset is in ped space, so it is rotated onto the ped's heading
    -- before it becomes a world position.
    local camX = coords.x + (math.sin(-rad) * forward.y) + (math.cos(rad) * offset.x * 0.0)
    local camY = coords.y + (math.cos(-rad) * forward.y)
    local camZ = coords.z + forward.z

    SetCamCoord(cam, camX, camY, camZ)
    PointCamAtCoord(cam, coords.x + point.x, coords.y + point.y, coords.z + point.z)
end

local function destroyCamera()
    if not cam then
        return
    end

    RenderScriptCams(false, true, 500, true, true)
    DestroyCam(cam, true)

    cam = nil
end

-- ----------------------------------------------------------------- menu ----

---@param settings table?
local function showMenu()
    if menuOpen then
        return
    end

    menuOpen = true

    local ped = cache.ped

    original = readAppearance(ped)
    working = readAppearance(ped)

    FreezeEntityPosition(ped, true)
    setCamera('default')

    ui:setAppearanceVisible(true)
end

local function hideMenu()
    if not menuOpen then
        return
    end

    menuOpen = false

    FreezeEntityPosition(cache.ped, false)
    destroyCamera()

    ui:setAppearanceVisible(false)
end

exports('showMenu', showMenu)

exports('hideMenu', function()
    if creatingCharacter then
        -- The page may already have closed itself; show it again rather than
        -- leaving the cursor over an empty screen.
        ui:setAppearanceVisible(true)

        return ui:notify({ type = 'info', text = 'Save your character to continue.' })
    end

    -- Closing without saving puts the ped back the way it was found.
    if original then
        applyAppearance(original)
    end

    hideMenu()
end)


-- ------------------------------------------------------------------ data ----

---Blacklist keys onto GTA component/prop ids (same map as server/main.lua).
local BLACKLIST_COMPONENT_IDS = {
    masks = 1, upperBody = 3, lowerBody = 4, bags = 5, shoes = 6,
    scarfAndChains = 7, shirts = 8, bodyArmor = 9, decals = 10, jackets = 11,
}

local BLACKLIST_PROP_IDS = { hats = 0, glasses = 1, ear = 2, watches = 6, bracelets = 7 }

---Head overlays that take a colour, and which palette it comes from.
local OVERLAY_PALETTE = {
    beard = 'hair', eyebrows = 'hair', chestHair = 'hair',
    makeUp = 'makeup', blush = 'makeup', lipstick = 'makeup',
}

---The blacklist entries that still bind this player, fetched when the menu
---opens (VIP / group exemptions are only known to the server).
---@type table?
local effectiveBlacklist

---@param entries table[]?
---@return { drawables: integer[], textures: integer[] }
local function mergeBlacklist(entries)
    local merged = { drawables = {}, textures = {} }

    for index = 1, #(entries or {}) do
        local entry = entries[index]

        for _, drawable in ipairs(entry.drawables or {}) do
            merged.drawables[#merged.drawables + 1] = drawable
        end

        for _, texture in ipairs(entry.textures or {}) do
            merged.textures[#merged.textures + 1] = texture
        end
    end

    return merged
end

---@param ped integer
---@return table
local function sexBlacklist(ped)
    local sex = GetEntityModel(ped) == FREEMODE_FEMALE and 'female' or 'male'

    return effectiveBlacklist and effectiveBlacklist[sex] or { components = {}, props = {}, hair = {} }
end

---@param ped integer
---@param id integer
---@return table
local function componentSettings(ped, id)
    local blacklist = sexBlacklist(ped)
    local entries

    for key, componentId in pairs(BLACKLIST_COMPONENT_IDS) do
        if componentId == id then
            entries = blacklist.components and blacklist.components[key]
        end
    end

    return {
        component_id = id,
        drawable = { min = 0, max = math.max(0, GetNumberOfPedDrawableVariations(ped, id) - 1) },
        texture = {
            min = 0,
            max = math.max(0, GetNumberOfPedTextureVariations(ped, id, GetPedDrawableVariation(ped, id)) - 1),
        },
        blacklist = mergeBlacklist(entries),
    }
end

---@param ped integer
---@param id integer
---@return table
local function propSettings(ped, id)
    local blacklist = sexBlacklist(ped)
    local entries

    for key, propId in pairs(BLACKLIST_PROP_IDS) do
        if propId == id then
            entries = blacklist.props and blacklist.props[key]
        end
    end

    return {
        prop_id = id,
        drawable = { min = -1, max = math.max(-1, GetNumberOfPedPropDrawableVariations(ped, id) - 1) },
        texture = {
            min = 0,
            max = math.max(0, GetNumberOfPedPropTextureVariations(ped, id, GetPedPropIndex(ped, id)) - 1),
        },
        blacklist = mergeBlacklist(entries),
    }
end

---@param palette 'hair' | 'makeup'
---@return integer[][]
local function paletteColours(palette)
    local colours = {}
    local count = palette == 'hair' and GetNumHairColors() or GetNumMakeupColors()

    for index = 0, count - 1 do
        local r, g, b

        if palette == 'hair' then
            r, g, b = GetPedHairRgbColor(index)
        else
            r, g, b = GetPedMakeupRgbColor(index)
        end

        colours[#colours + 1] = { r or 0, g or 0, b or 0 }
    end

    return colours
end

---@param ped integer
---@return table
local function hairSettings(ped)
    local hairColours = paletteColours('hair')

    return {
        style = { min = 0, max = math.max(0, GetNumberOfPedDrawableVariations(ped, 2) - 1) },
        color = { items = hairColours },
        highlight = { items = hairColours },
        texture = { min = 0, max = math.max(0, GetNumberOfPedTextureVariations(ped, 2, GetPedDrawableVariation(ped, 2)) - 1) },
        blacklist = mergeBlacklist(sexBlacklist(ped).hair),
    }
end

---Every slider range and list the menu renders, in the shape its bundle
---reads (illenium-appearance's): `ped.model.items`, `hair.color.items`,
---per-overlay `style`/`opacity`/`color`, and so on. The old flat shape
---(`ped = { ... }`) crashed the menu the moment it opened.
---@param ped integer
---@return table
local function buildSettings(ped)
    local components = {}

    for index = 1, #constants.pedComponentIds do
        components[index] = componentSettings(ped, constants.pedComponentIds[index])
    end

    local props = {}

    for index = 1, #constants.pedPropsIds do
        props[index] = propSettings(ped, constants.pedPropsIds[index])
    end

    local mix = { min = 0, max = 10, factor = 0.1 }
    local parent = { min = 0, max = 45 }

    local faceFeatures = {}

    for index = 1, #constants.faceFeatures do
        faceFeatures[constants.faceFeatures[index]] = { min = -10, max = 10, factor = 0.1 }
    end

    local palettes = { hair = paletteColours('hair'), makeup = paletteColours('makeup') }
    local headOverlays = {}

    for index = 1, #constants.headOverlays do
        local name = constants.headOverlays[index]
        local palette = OVERLAY_PALETTE[name]

        headOverlays[name] = {
            style = { min = 0, max = math.max(0, GetPedHeadOverlayNum(index - 1) - 1) },
            opacity = { min = 0, max = 10, factor = 0.1 },
            color = palette and { items = palettes[palette] } or nil,
        }
    end

    return {
        -- The editor is a character creator: its model list is the gender
        -- switch, so it offers the two freemode peds only. Other whitelisted
        -- peds can still be applied by the server (SetAppearance).
        ped = { model = { items = { 'mp_m_freemode_01', 'mp_f_freemode_01' } } },
        tattoos = { items = {} },
        components = components,
        props = props,
        headBlend = {
            shapeFirst = parent, shapeSecond = parent, shapeThird = parent,
            skinFirst = parent, skinSecond = parent, skinThird = parent,
            shapeMix = mix, skinMix = mix, thirdMix = mix,
        },
        faceFeatures = faceFeatures,
        headOverlays = headOverlays,
        hair = hairSettings(ped),
        eyeColor = { min = 0, max = #constants.eyeColors - 1 },
    }
end

---@return table
local function settingsAndData()
    local ped = cache.ped

    return {
        appearanceData = readAppearance(ped),
        appearanceSettings = buildSettings(ped),
        -- Clothing collections (addon packs); none on this server.
        collections = { components = {}, props = {} },
        config = creatingCharacter and FIRST_CHARACTER_CONFIG or clientConfig.defaultCustomizationConfig,
    }
end

---What the menu needs to render itself: the current appearance, the limits
---for every slider and list, and the menu config.
---@return table
exports('getSettingsAndData', function()
    if not effectiveBlacklist then
        effectiveBlacklist = lib.callback.await('appearance:server:getBlacklist', false)
    end

    return settingsAndData()
end)

exports('getAppearance', function()
    return readAppearance(cache.ped)
end)

exports('getPedAppearance', function(ped)
    return readAppearance(ped or cache.ped)
end)

exports('getPedComponents', function(ped)
    return readComponents(ped or cache.ped)
end)

exports('getPedProps', function(ped)
    return readProps(ped or cache.ped)
end)

exports('getPedModel', function(ped)
    return getPedModelName(ped or cache.ped)
end)

exports('getPedTattoos', function()
    return appliedTattoos
end)

-- ---------------------------------------------------------------- setters ----

exports('setPedComponents', function(ped, components)
    applyComponents(ped or cache.ped, components)
end)

exports('setPedProps', function(ped, props)
    applyProps(ped or cache.ped, props)
end)

exports('setPedTattoos', function(ped, tattoos)
    appliedTattoos = tattoos or {}

    applyHair(ped or cache.ped, readHair(ped or cache.ped))
end)

---Dresses any local ped (lobby podium, previews). The caller creates the ped
---with the right model; everything else is applied to that ped only. It used
---to ignore `ped` and restyle the player, so lobby peds stood bald in default
---clothes and could swap the player's own model.
exports('setPedAppearance', function(ped, appearance)
    if type(appearance) ~= 'table' then
        return
    end

    if not ped or ped == cache.ped or ped == PlayerPedId() then
        return applyAppearance(appearance)
    end

    if not DoesEntityExist(ped) then
        return
    end

    applyHeadBlend(ped, appearance.headBlend)
    applyFaceFeatures(ped, appearance.faceFeatures)
    applyHeadOverlays(ped, appearance.headOverlays)
    applyComponents(ped, appearance.components)
    applyProps(ped, appearance.props)

    if appearance.eyeColor then
        SetPedEyeColor(ped, appearance.eyeColor)
    end

    local hair = appearance.hair

    if hair then
        SetPedComponentVariation(ped, 2, hair.style or 0, hair.texture or 0, 0)
        SetPedHairColor(ped, hair.color or 0, hair.highlight or 0)
    end

    ClearPedDecorations(ped)

    local sex = GetEntityModel(ped) == FREEMODE_FEMALE and 'female' or 'male'
    local decoration = hair and constants.hairDecorations[sex] and constants.hairDecorations[sex][hair.style or 0]

    if decoration then
        AddPedDecorationFromHashes(ped, decoration[1], decoration[2])
    end

    for _, tattoo in ipairs(type(appearance.tattoos) == 'table' and appearance.tattoos or {}) do
        if type(tattoo) == 'table' and tattoo.collection and tattoo.hash then
            AddPedDecorationFromHashes(ped, joaat(tattoo.collection), joaat(tattoo.hash))
        end
    end
end)

exports('setPlayerAppearance', function(appearance)
    applyAppearance(appearance)

    working = readAppearance(cache.ped)
end)

exports('setPlayerModel', function(model)
    return applyModel(model)
end)

-- ---------------------------------------------------------------- editing ----

---@param model string
---@return table
exports('changeModel', function(model)
    applyModel(model)

    -- The new ped is not the one showMenu froze.
    if menuOpen then
        FreezeEntityPosition(cache.ped, true)
    end

    working = readAppearance(cache.ped)

    -- The menu rebuilds itself from this: the new ped has different drawable
    -- counts and palettes, so it needs new settings, not just data.
    return settingsAndData()
end)

---@param component table
---@return table
exports('changeComponent', function(component)
    applyComponents(cache.ped, { component })

    working = readAppearance(cache.ped)

    -- The menu wants this component's new ranges (the texture count changes
    -- with the drawable), not the whole appearance.
    return componentSettings(cache.ped, component.component_id)
end)

---@param prop table
---@return table
exports('changeProp', function(prop)
    applyProps(cache.ped, { prop })

    working = readAppearance(cache.ped)

    return propSettings(cache.ped, prop.prop_id)
end)

exports('changeHeadBlend', function(headBlend)
    applyHeadBlend(cache.ped, headBlend)
end)

exports('changeFaceFeature', function(features)
    applyFaceFeatures(cache.ped, features)
end)

exports('changeHeadOverlay', function(overlays)
    applyHeadOverlays(cache.ped, overlays)
end)

---@param hair table
---@return table
exports('changeHair', function(hair)
    applyHair(cache.ped, hair)

    working = readAppearance(cache.ped)

    -- Hair settings (the texture range follows the style); the menu stores
    -- this as appearanceSettings.hair.
    return hairSettings(cache.ped)
end)

exports('changeEyeColor', function(eyeColor)
    SetPedEyeColor(cache.ped, eyeColor or 0)
end)

-- --------------------------------------------------------------- tattoos ----

---@param sex 'male' | 'female'
---@param tattoo table
---@return string?
local function resolveTattooHash(sex, tattoo)
    return sex == 'female' and tattoo.hashFemale or tattoo.hashMale
end

---@param data table
exports('applyTattoo', function(data)
    local ped = cache.ped
    local sex = GetEntityModel(ped) == FREEMODE_FEMALE and 'female' or 'male'
    local hash = resolveTattooHash(sex, data)

    if not hash then
        return
    end

    appliedTattoos[#appliedTattoos + 1] = {
        name = data.name,
        collection = data.collection,
        hash = hash,
        zone = data.zone,
    }

    AddPedDecorationFromHashes(ped, joaat(data.collection), joaat(hash))
end)

---Shown while the player is hovering an entry, so it has to come off again
---without disturbing the tattoos they have actually chosen.
---@param data table?
exports('previewTattoo', function(data)
    local ped = cache.ped

    ClearPedDecorations(ped)

    for index = 1, #appliedTattoos do
        local tattoo = appliedTattoos[index]

        AddPedDecorationFromHashes(ped, joaat(tattoo.collection), joaat(tattoo.hash))
    end

    if not data then
        return
    end

    local sex = GetEntityModel(ped) == FREEMODE_FEMALE and 'female' or 'male'
    local hash = resolveTattooHash(sex, data)

    if hash then
        AddPedDecorationFromHashes(ped, joaat(data.collection), joaat(hash))
    end
end)

---@param data table
exports('deleteTattoo', function(data)
    for index = #appliedTattoos, 1, -1 do
        if appliedTattoos[index].name == data.name then
            table.remove(appliedTattoos, index)
        end
    end

    local ped = cache.ped

    ClearPedDecorations(ped)

    for index = 1, #appliedTattoos do
        local tattoo = appliedTattoos[index]

        AddPedDecorationFromHashes(ped, joaat(tattoo.collection), joaat(tattoo.hash))
    end
end)

-- --------------------------------------------------------------- clothes ----

---@param data table
exports('wearClothes', function(data)
    local set = constants.dataClothes and constants.dataClothes[data and data.type or '']

    if not set then
        return
    end

    local sex = GetEntityModel(cache.ped) == FREEMODE_FEMALE and 'female' or 'male'

    applyComponents(cache.ped, (function()
        local out = {}

        for index = 1, #(set.components[sex] or {}) do
            local pair = set.components[sex][index]

            out[index] = { component_id = pair[1], drawable = pair[2], texture = 0 }
        end

        return out
    end)())
end)

---@param clothes table
exports('removeClothes', function(clothes)
    local set = constants.dataClothes and constants.dataClothes[clothes and clothes.type or '']

    if not set then
        return
    end

    local sex = GetEntityModel(cache.ped) == FREEMODE_FEMALE and 'female' or 'male'

    for index = 1, #(set.components[sex] or {}) do
        SetPedComponentVariation(cache.ped, set.components[sex][index][1], 0, 0, 0)
    end
end)

-- ------------------------------------------------------------ save / reset ----

---@return table
exports('resetAppearance', function()
    if original then
        applyAppearance(original)
    end

    working = readAppearance(cache.ped)

    -- The menu destructures { appearanceData }.
    return { appearanceData = working }
end)

---Goes through the server: the blacklist is enforced there, so a save that
---the menu allowed can still legitimately come back refused.
---@param appearanceData table?
---@return boolean success
---@return string? error
exports('saveAppearance', function(appearanceData)
    local payload = appearanceData or readAppearance(cache.ped)

    local success, err = lib.callback.await('appearance:server:save', false, payload)

    if not success then
        ui:notify({ type = 'error', text = err or 'Could not save your appearance.' })

        return false, err
    end

    creatingCharacter = false
    original = payload
    working = payload

    hideMenu()

    ui:notify({ type = 'success', text = 'Appearance saved.' })

    return true
end)

-- ---------------------------------------------------------------- camera ----

exports('setCamera', setCamera)

exports('turnAround', function()
    SetEntityHeading(cache.ped, GetEntityHeading(cache.ped) + 180.0)
end)

---@param direction integer -1 or 1
exports('rotateCamera', function(direction)
    SetEntityHeading(cache.ped, GetEntityHeading(cache.ped) + (direction < 0 and -15.0 or 15.0))
end)

exports('startPlayerCustomization', function()
    showMenu()
end)

-- ------------------------------------------------------------------ load ----

---Applied on spawn so a returning player looks like themselves before they
---are visible to anyone.
RegisterNetEvent('appearance:client:apply', applyAppearance)

CreateThread(function()
    while GetResourceState('core') ~= 'started' do
        Wait(200)
    end

    CoreClient.awaitPlayerLoaded()

    local saved = lib.callback.await('appearance:server:get', false)

    if type(saved) == 'table' and saved.model then
        applyAppearance(saved)

        return
    end

    -- No character yet: everyone starts as the default freemode male (not
    -- whatever ped the session happened to hand out) and goes straight into
    -- the creator. It reopens on every join until they save once.
    applyModel('mp_m_freemode_01')

    local deadline = GetGameTimer() + 15000

    while (GetResourceState('ui') ~= 'started' or not LocalPlayer.state.uisReady) and GetGameTimer() < deadline do
        Wait(200)
    end

    -- Let the spawn teleport and fade settle so the camera frames the ped
    -- where it actually stands.
    Wait(1500)

    creatingCharacter = true

    showMenu()

    ui:notify({ type = 'info', text = 'Create your character: pick a gender, parents and features, then save.' })
end)

---Reopen the creator at any time outside a match.
RegisterCommand('character', function()
    if menuOpen then
        return
    end

    if GetResourceState('hopouts') == 'started' and exports.hopouts:isInMatch() then
        return ui:notify({ type = 'error', text = 'You cannot edit your character during a match.' })
    end

    if IsEntityDead(cache.ped) or IsPedInAnyVehicle(cache.ped, false) then
        return ui:notify({ type = 'error', text = 'You need to be on foot and alive to edit your character.' })
    end

    if GetEntityModel(cache.ped) ~= FREEMODE_MALE and GetEntityModel(cache.ped) ~= FREEMODE_FEMALE then
        applyModel('mp_m_freemode_01')
    end

    showMenu()
end, false)

TriggerEvent('chat:addSuggestion', '/character', 'Open the character creator (gender, parents, face, hair, clothes)')

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then
        return
    end

    destroyCamera()
    FreezeEntityPosition(cache.ped, false)
end)
