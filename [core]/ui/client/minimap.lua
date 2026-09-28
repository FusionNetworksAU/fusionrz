local mmBase = nil
local mmAnchor = nil

local mmOffsetX = 0.0
local mmOffsetY = 0.0
local mmScale = 1.0
local mmUseCustomPosition = false
local minimapRadarEnabled = true
local hudEditorActive = false
local radarHiddenByUi = false
local radarWantedBeforeUi = false
local mmAnchorPushSuppressed = false
local hudNuiReady = false
local pendingAnchorPush = false
local mmAnchorOverride = nil

---@type { x: number, y: number, scale?: number }?
local mmLayoutOverride = nil
local applyLayoutOverride

local OFFSET_CLAMP = 1.0
local SCALE_MIN = 0.5
local SCALE_MAX = 2.0
local ANCHOR_EPS = 0.0001

local KVP_KEYS = {
    offsetX = 'fusionrz_v5:minimapOffsetX',
    offsetY = 'fusionrz_v5:minimapOffsetY',
    scale = 'fusionrz_v5:minimapScale',
    useCustom = 'fusionrz_v5:minimapUseCustom',
}

local MM_BASE = {
    minimap = { x = 0.0, y = -0.022, w = 0.1638, h = 0.183 },
    minimap_mask = { x = 0.0, y = 0.005, w = 0.128, h = 0.20 },
    minimap_blur = { x = -0.01, y = 0.05, w = 0.262, h = 0.300 },
}

local BIGMAP_BASE = {
    bigmap = { x = -0.003975, y = 0.022, w = 0.364, h = 0.460416666 },
    bigmap_mask = { x = 0.145, y = 0.015, w = 0.176, h = 0.395 },
    bigmap_blur = { x = -0.019, y = 0.022, w = 0.262, h = 0.464 },
}

local mmCal = {
    offsetX = 0.0,
    offsetY = -0.025,
    width = 0.034,
    height = -0.015,
}

local function sendNui(action, data)
    SendNUIMessage({ action = action, data = data })
end

local function clampOffset(v)
    return math.max(-OFFSET_CLAMP, math.min(OFFSET_CLAMP, v))
end

local function clampScale(v)
    return math.max(SCALE_MIN, math.min(SCALE_MAX, v))
end

local function layoutPivot()
    return MM_BASE.minimap_mask.x + mmCal.offsetX,
        MM_BASE.minimap_mask.y + mmCal.offsetY
end

local function anchorsEqual(a, b)
    if not a or not b then return false end

    return math.abs(a.LeftX - b.LeftX) < ANCHOR_EPS
        and math.abs(a.TopY - b.TopY) < ANCHOR_EPS
        and math.abs(a.Width - b.Width) < ANCHOR_EPS
        and math.abs(a.Height - b.Height) < ANCHOR_EPS
end

local function pushAnchorToNui(anchor, force, editorPreview, offsetX, offsetY, scale)
    if not anchor then return end

    if mmAnchorPushSuppressed and not force then
        mmAnchor = anchor
        return
    end

    if not hudNuiReady and not force then
        mmAnchor = anchor
        pendingAnchorPush = true
        return
    end

    if not force and mmAnchor and anchorsEqual(mmAnchor, anchor) then
        mmAnchor = anchor
        return
    end

    mmAnchor = anchor
    pendingAnchorPush = false

    local ox = clampOffset(tonumber(offsetX) or mmOffsetX)
    local oy = clampOffset(tonumber(offsetY) or mmOffsetY)
    local sc = clampScale(tonumber(scale) or mmScale)
    local scalarX, scalarY = GetMinimapOffsetScreenScalars(sc)

    sendNui('setMinimapAnchor', {
        left = anchor.LeftX,
        top = anchor.TopY,
        width = anchor.Width,
        height = anchor.Height,
        centerX = anchor.CenterX,
        centerY = anchor.CenterY,
        scalarX = scalarX,
        scalarY = scalarY,
        offsetX = ox,
        offsetY = oy,
        scale = sc,
        editorPreview = editorPreview == true,
    })
end

local function ensureMinimapReady()
    if mmBase then return true end
    RestoreSquaremap(true)
    return mmBase ~= nil
end

function SetHudNuiReady(ready)
    hudNuiReady = ready == true

    if hudNuiReady and pendingAnchorPush and mmAnchor then
        pushAnchorToNui(mmAnchor, true, false, mmOffsetX, mmOffsetY, mmScale)
    end
end

local function scaledLayout(baseX, baseY, baseW, baseH, offsetX, offsetY, scale)
    local pivotX, pivotY = layoutPivot()
    return pivotX + (baseX - pivotX) * scale + offsetX,
        pivotY + (baseY - pivotY) * scale + offsetY,
        baseW * scale,
        baseH * scale
end

local function placeComponent(name, base, offsetX, offsetY, scale, pivotX, pivotY)
    local posX = pivotX + (base.x - pivotX) * scale + offsetX
    local posY = pivotY + (base.y - pivotY) * scale + offsetY
    local sizeX = base.w * scale
    local sizeY = base.h * scale
    local p, s = AdjustNormalized16_9ValuesForCurrentAspectRatio('L', posX, posY, sizeX, sizeY, true)
    SetMinimapComponentPosition(name, 'L', 'B', p.x, p.y, s.x, s.y)
end

local function placeBigmapComponents(offsetX, offsetY)
    offsetX = clampOffset(offsetX or mmOffsetX)
    offsetY = clampOffset(offsetY or mmOffsetY)

    for name, base in pairs(BIGMAP_BASE) do
        local p, s = AdjustNormalized16_9ValuesForCurrentAspectRatio(
            'L', base.x + offsetX, base.y + offsetY, base.w, base.h, true
        )
        SetMinimapComponentPosition(name, 'L', 'B', p.x, p.y, s.x, s.y)
    end
end

local function computeMinimapAnchor(offsetX, offsetY, scale)
    local mask = MM_BASE.minimap_mask
    local anchorX, anchorY, anchorW, anchorH = scaledLayout(
        mask.x + mmCal.offsetX,
        mask.y + mmCal.offsetY,
        mask.w + mmCal.width,
        mask.h + mmCal.height,
        offsetX,
        offsetY,
        scale
    )
    return GetAnchorScreenCoords('L', 'B', anchorX, anchorY, anchorW, anchorH)
end

function MoveSquaremapMinimap(offsetX, offsetY, scale, editorPreview)
    if not mmBase then return nil end

    if offsetX ~= nil then mmOffsetX = clampOffset(offsetX) end
    if offsetY ~= nil then mmOffsetY = clampOffset(offsetY) end
    if scale ~= nil then mmScale = clampScale(scale) end

    if mmLayoutOverride then
        return applyLayoutOverride()
    end

    local pivotX, pivotY = layoutPivot()
    for _, name in ipairs({ 'minimap', 'minimap_mask', 'minimap_blur' }) do
        placeComponent(name, mmBase[name], mmOffsetX, mmOffsetY, mmScale, pivotX, pivotY)
    end
    placeBigmapComponents(mmOffsetX, mmOffsetY)

    local anchor = computeMinimapAnchor(mmOffsetX, mmOffsetY, mmScale)

    if mmAnchorOverride then
        return anchor
    end

    local force = editorPreview == true
    pushAnchorToNui(anchor, force, force, mmOffsetX, mmOffsetY, mmScale)
    return anchor
end

---@param layout { alignX?: string, alignY?: string, x: number, y: number, w: number, h: number }?
---@return boolean restored true when the squaremap layout was restored (only for the nil call)
function SetMinimapAnchorOverride(layout)
    if type(layout) ~= 'table' then
        if not mmAnchorOverride then
            return false
        end

        mmAnchorOverride = nil

        local anchor = MoveSquaremapMinimap(mmOffsetX, mmOffsetY, mmScale)
        if not anchor then
            return false
        end

        CommitMinimapLayout()
        return true
    end

    local anchor = GetAnchorScreenCoords(
        layout.alignX or 'L',
        layout.alignY or 'T',
        layout.x, layout.y, layout.w, layout.h
    )

    if mmAnchorOverride and mmAnchor and anchorsEqual(mmAnchor, anchor) then
        return false
    end

    mmAnchorOverride = layout
    pushAnchorToNui(anchor, true, false, mmOffsetX, mmOffsetY, mmScale)
    return false
end

exports('setMinimapAnchorOverride', SetMinimapAnchorOverride)

exports('getMinimapAnchor', function()
    return mmAnchor
end)

---@param base { x: number, y: number, w: number, h: number }
---@return number x, number y, number w, number h
local function baseToTopSpace(base)
    local mask = MM_BASE.minimap_mask
    return base.x - mask.x, (base.y - base.h) - (mask.y - mask.h), base.w, base.h
end

---@return table? anchor
applyLayoutOverride = function()
    local layout = mmLayoutOverride
    if not layout or not ensureMinimapReady() then
        return nil
    end

    local scale = clampScale(layout.scale or 1.0)

    for _, name in ipairs({ 'minimap', 'minimap_mask', 'minimap_blur' }) do
        local bx, by, bw, bh = baseToTopSpace(MM_BASE[name])
        local p, s = AdjustNormalized16_9ValuesForCurrentAspectRatio(
            'L', layout.x + bx * scale, layout.y + by * scale, bw * scale, bh * scale, true
        )
        SetMinimapComponentPosition(name, 'L', 'T', p.x, p.y, s.x, s.y)
    end

    local mask = MM_BASE.minimap_mask
    local anchor = GetAnchorScreenCoords(
        'L', 'T',
        layout.x + mmCal.offsetX * scale,
        layout.y + (mmCal.offsetY - mmCal.height) * scale,
        (mask.w + mmCal.width) * scale,
        (mask.h + mmCal.height) * scale
    )

    pushAnchorToNui(anchor, false, false, mmOffsetX, mmOffsetY, mmScale)
    return anchor
end

---@param layout { x: number, y: number, scale?: number }?
---@return boolean restored
function SetMinimapLayoutOverride(layout)
    if type(layout) ~= 'table' then
        if not mmLayoutOverride then
            return false
        end

        mmLayoutOverride = nil

        local anchor = MoveSquaremapMinimap(mmOffsetX, mmOffsetY, mmScale)
        if not anchor then
            return false
        end

        CommitMinimapLayout()
        return true
    end

    mmLayoutOverride = {
        x = tonumber(layout.x) or 0.0,
        y = tonumber(layout.y) or 0.0,
        scale = clampScale(tonumber(layout.scale) or 1.0),
    }

    applyLayoutOverride()
    return false
end

exports('setMinimapLayoutOverride', SetMinimapLayoutOverride)

---@param name 'minimap' | 'minimap_mask' | 'minimap_blur' | 'bigmap' | 'bigmap_mask' | 'bigmap_blur'
---@param alignX 'L' | 'C' | 'R'
---@param alignY 'T' | 'C' | 'B'
exports('placeMinimapComponent', function(name, alignX, alignY, x, y, w, h)
    local p, s = AdjustNormalized16_9ValuesForCurrentAspectRatio(alignX, x, y, w, h, true)
    SetMinimapComponentPosition(name, alignX, alignY, p.x, p.y, s.x, s.y)
end)

---@param alignX 'L' | 'C' | 'R'
---@param alignY 'T' | 'C' | 'B'
---@return table anchor { LeftX, TopY, RightX, BottomY, Width, Height, CenterX, CenterY }
exports('computeMinimapAnchor', function(alignX, alignY, x, y, w, h)
    return GetAnchorScreenCoords(alignX, alignY, x, y, w, h)
end)

local function pushPreviewAnchor(offsetX, offsetY, scale)
    if not ensureMinimapReady() then return nil end
    return MoveSquaremapMinimap(
        offsetX or mmOffsetX,
        offsetY or mmOffsetY,
        scale or mmScale,
        true
    )
end

function GetMinimapOffsetScreenScalars(scale)
    if not mmBase then return 1.0, 1.0 end

    scale = clampScale(scale or mmScale)
    local a1 = computeMinimapAnchor(0.0, 0.0, scale)
    local a2 = computeMinimapAnchor(0.1, 0.0, scale)
    local a3 = computeMinimapAnchor(0.0, 0.1, scale)
    if not a1 or not a2 or not a3 then return 1.0, 1.0 end

    local sx = (a2.LeftX - a1.LeftX) / 0.1
    local sy = (a3.TopY - a1.TopY) / 0.1
    if math.abs(sx) < 0.001 then sx = 1.0 end
    if math.abs(sy) < 0.001 then sy = 1.0 end
    return sx, sy
end

function CommitMinimapLayout()
    if IsBigmapActive() then return end
    SetBigmapActive(true, false)
    Wait(50)
    SetBigmapActive(false, false)
end

local function loadSquaremapMask()
    lib.requestStreamedTextureDict('squaremap')

    SetMinimapClipType(0)
    AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', 'squaremap', 'radarmasksm')
    AddReplaceTexture('platform:/textures/graphics', 'radarmask1g', 'squaremap', 'radarmasksm')
end

function RestoreSquaremap(skipNetworkWait)
    if not skipNetworkWait then
        while not NetworkIsPlayerActive(PlayerId()) do
            Wait(250)
        end
    end

    mmBase = MM_BASE
    loadSquaremapMask()
    MoveSquaremapMinimap(mmOffsetX, mmOffsetY, mmScale)
    SetBlipAlpha(GetNorthRadarBlip(), 0)
    SetMinimapClipType(0)
    CommitMinimapLayout()
    RefreshMinimapRadarVisibility()
end

function SendMinimapAnchorToNui(force)
    if mmAnchor then
        pushAnchorToNui(mmAnchor, force, false, mmOffsetX, mmOffsetY, mmScale)
        return
    end

    local anchor = MoveSquaremapMinimap(mmOffsetX, mmOffsetY, mmScale)
    if anchor and force then
        pushAnchorToNui(anchor, true, false, mmOffsetX, mmOffsetY, mmScale)
    end
end

local function pushMinimapSettingsToNui()
    sendNui('setMinimapSettings', {
        offsetX = mmOffsetX,
        offsetY = mmOffsetY,
        scale = mmScale,
        useCustomPosition = mmUseCustomPosition,
    })
end

local function persistMinimapKvp()
    SetResourceKvp(KVP_KEYS.offsetX, tostring(mmOffsetX))
    SetResourceKvp(KVP_KEYS.offsetY, tostring(mmOffsetY))
    SetResourceKvp(KVP_KEYS.scale, tostring(mmScale))
    SetResourceKvp(KVP_KEYS.useCustom, mmUseCustomPosition and 'true' or 'false')
end

local function loadMinimapFromKvp()
    mmOffsetX = clampOffset(tonumber(GetResourceKvpString(KVP_KEYS.offsetX) or '') or 0.0)
    mmOffsetY = clampOffset(tonumber(GetResourceKvpString(KVP_KEYS.offsetY) or '') or 0.0)
    mmScale = clampScale(tonumber(GetResourceKvpString(KVP_KEYS.scale) or '') or 1.0)
    mmUseCustomPosition = GetResourceKvpString(KVP_KEYS.useCustom) == 'true'
        or math.abs(mmOffsetX) > 0.0001
        or math.abs(mmOffsetY) > 0.0001
        or math.abs(mmScale - 1.0) > 0.0001
end

local function isUiBlockingRadar()
    if not minimapRadarEnabled then return true end
    if hudEditorActive then return true end
    if IsMenuVisible() then return true end
    if IsPauseMenuVisible() then return true end
    if IsRankedMenuVisible() then return true end
    return false
end

function SetMinimapRadarEnabled(enabled)
    minimapRadarEnabled = enabled ~= false
    if not minimapRadarEnabled then
        radarWantedBeforeUi = false
    end
    RefreshMinimapRadarVisibility()
end

function RefreshMinimapRadarVisibility()
    if isUiBlockingRadar() then
        if not radarHiddenByUi then
            radarWantedBeforeUi = not IsRadarHidden()
            radarHiddenByUi = true
        end
        if not IsRadarHidden() then
            DisplayRadar(false)
        end
        return
    end

    if radarHiddenByUi then
        radarHiddenByUi = false
        if radarWantedBeforeUi and minimapRadarEnabled then
            DisplayRadar(true)
        end
    elseif not minimapRadarEnabled and not IsRadarHidden() then
        DisplayRadar(false)
    end
end

exports('refreshMinimapRadarVisibility', RefreshMinimapRadarVisibility)

function SetMinimapScale(scale)
    if scale then
        mmScale = clampScale(scale)
    end
    MoveSquaremapMinimap(mmOffsetX, mmOffsetY, mmScale)
end

function TryApplyMinimapOffset(offsetX, offsetY, scale, editorPreview)
    mmUseCustomPosition = true
    MoveSquaremapMinimap(offsetX, offsetY, scale, editorPreview == true)
    if not editorPreview then
        CommitMinimapLayout()
    end
    return true
end

function IsHudEditorActive()
    return hudEditorActive
end

function SetHudEditorActive(active)
    hudEditorActive = active == true

    if hudEditorActive then
        mmAnchorPushSuppressed = true
        RefreshMinimapRadarVisibility()
        TriggerScreenblurFadeOut(0)

        return
    end


    mmAnchorPushSuppressed = false
    RefreshMinimapRadarVisibility()

    if mmAnchor then
        pushAnchorToNui(mmAnchor, true)
    else
        local anchor = MoveSquaremapMinimap(mmOffsetX, mmOffsetY, mmScale)
        if anchor then
            pushAnchorToNui(anchor, true)
        end
    end
end

RegisterNUICallback('setMinimapOffset', function(data, cb)
    if type(data) == 'table' then
        TryApplyMinimapOffset(
            tonumber(data.offsetX) or 0.0,
            tonumber(data.offsetY) or 0.0,
            tonumber(data.scale),
            data.editorPreview == true
        )
    end
    cb(true)
end)

RegisterNUICallback('previewMinimapAnchor', function(data, cb)
    if type(data) == 'table' then
        pushPreviewAnchor(tonumber(data.offsetX), tonumber(data.offsetY), tonumber(data.scale))
    else
        pushPreviewAnchor(mmOffsetX, mmOffsetY, mmScale)
    end
    cb(true)
end)

RegisterNUICallback('requestMinimapAnchor', function(_, cb)
    if hudEditorActive then
        pushPreviewAnchor(mmOffsetX, mmOffsetY, mmScale)
    else
        SendMinimapAnchorToNui(true)
    end
    cb(true)
end)

RegisterNUICallback('setHudEditorActive', function(data, cb)
    local wantActive = data == true
        or data == 1
        or data == 'true'
        or (type(data) == 'table' and (data.active == true or data[1] == true))

    if wantActive then
        ensureMinimapReady()
        SetHudEditorActive(true)
        pushMinimapSettingsToNui()
        pushPreviewAnchor(mmOffsetX, mmOffsetY, mmScale)
    else
        SetHudEditorActive(false)
        MoveSquaremapMinimap(mmOffsetX, mmOffsetY, mmScale)
        CommitMinimapLayout()
    end
    cb(true)
end)

RegisterNUICallback('saveMinimapSettings', function(data, cb)
    if type(data) == 'table' then
        mmOffsetX = clampOffset(tonumber(data.offsetX) or mmOffsetX)
        mmOffsetY = clampOffset(tonumber(data.offsetY) or mmOffsetY)
        mmScale = clampScale(tonumber(data.scale) or mmScale)
        mmUseCustomPosition = true
        persistMinimapKvp()
        pushMinimapSettingsToNui()

        if hudEditorActive then
            pushPreviewAnchor(mmOffsetX, mmOffsetY, mmScale)
        else
            MoveSquaremapMinimap(mmOffsetX, mmOffsetY, mmScale)
            CommitMinimapLayout()
        end
    end
    cb(true)
end)

RegisterNUICallback('resetMinimapPosition', function(_, cb)
    mmOffsetX = 0.0
    mmOffsetY = 0.0
    mmScale = 1.0
    mmUseCustomPosition = false
    persistMinimapKvp()
    pushMinimapSettingsToNui()

    if hudEditorActive then
        pushPreviewAnchor(mmOffsetX, mmOffsetY, mmScale)
    else
        MoveSquaremapMinimap(mmOffsetX, mmOffsetY, mmScale)
        CommitMinimapLayout()
    end

    cb(true)
end)

CreateThread(function()
    local playerState = LocalPlayer.state

    while not playerState.uisReady do
        Wait(100)
    end

    SetHudNuiReady(true)
    loadMinimapFromKvp()
    pushMinimapSettingsToNui()

    while not playerState.isLoaded do
        Wait(100)
    end

    Wait(500)
    RestoreSquaremap(true)
end)
