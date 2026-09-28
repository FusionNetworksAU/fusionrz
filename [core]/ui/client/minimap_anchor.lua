local RATIO_16_9 = 1.7777777910233

local function vec2(x, y)
    if vector2 then
        return vector2(x, y)
    end
    return { x = x, y = y }
end

function IsSuperWideScreen()
    return GetAspectRatio(true) > RATIO_16_9
end

function GetWideScreen()
    local WIDESCREEN_ASPECT = 1.5
    local fLogicalAspectRatio = GetAspectRatio(false)
    local w, h = GetActualScreenResolution()
    local fPhysicalAspectRatio = w / h

    if fPhysicalAspectRatio <= WIDESCREEN_ASPECT then
        return false
    end

    return fLogicalAspectRatio > WIDESCREEN_ASPECT
end

function AdjustForSuperWidescreen(x, w)
    if not IsSuperWideScreen() then
        return x, w
    end

    local difference = (RATIO_16_9) / GetAspectRatio(false)
    x = 0.5 - ((0.5 - x) * difference)
    w = w * difference

    return x, w
end

function GetDifferenceFrom_16_9_ToCurrentAspectRatio()
    local fOffsetValue = 0.0

    if not IsSuperWideScreen() then
        local width, height = GetActualScreenResolution()
        local fAspectRatio = width / height
        local fMarginRatio = (1.0 - GetSafeZoneSize()) * 0.5
        local fDifferenceInMarginSize = fMarginRatio * RATIO_16_9 - fAspectRatio
        fOffsetValue = (1.0 - (fAspectRatio / RATIO_16_9)) - fDifferenceInMarginSize * 0.5
    end

    return fOffsetValue
end

function GetMinSafeZone(aspectRatio, bScript)
    local sz = GetSafeZoneSize()
    local safezoneSizeX, safezoneSizeY = sz, sz

    if aspectRatio < 1.0 then
        safezoneSizeX = 1.0 - ((1.0 - safezoneSizeX) + (1.0 - aspectRatio))
    end

    local width, height = GetActualScreenResolution()
    local offsetW = (width - (width * safezoneSizeX)) * 0.5
    local offsetH = (height - (height * safezoneSizeY)) * 0.5

    local x0 = math.ceil(offsetW) / width
    local y0 = math.ceil(offsetH) / height
    local x1 = math.floor(width - offsetW) / width
    local y1 = math.floor(height - offsetH) / height

    if bScript and IsSuperWideScreen() then
        local fDifference = RATIO_16_9 / GetAspectRatio(true)
        local fOffsetRelative = (width - (width * fDifference)) * 0.5 / width
        x0 = x0 + fOffsetRelative
        x1 = x1 - fOffsetRelative
    end

    return x0, y0, x1, y1
end

function AdjustNormalized16_9ValuesForCurrentAspectRatio(hAlign, x, y, w, h, isMinimap)
    local currentRatio = GetAspectRatio(false)

    if IsSuperWideScreen() then
        currentRatio = RATIO_16_9
    end

    local fScalar = RATIO_16_9 / currentRatio
    local fAdjustPos = 1.0 - fScalar

    if math.abs(fAdjustPos) < 0.001 then
        fAdjustPos = 0.0
    end

    w = w * fScalar
    x = x * fScalar

    if hAlign == 'C' then
        x = x + (fAdjustPos * 0.5)
    elseif hAlign == 'R' and isMinimap then
        x = x + (1.0 - (currentRatio / RATIO_16_9))
    end

    if not isMinimap then
        x, w = AdjustForSuperWidescreen(x, w)
    end

    return vec2(x, y), vec2(w, h)
end

function CalculateHudPosition(offset, size, alignX, alignY)
    local x0, y0, x1, y1 = GetMinSafeZone(1.0)
    local safeMin, safeMax = vec2(x0, y0), vec2(x1, y1)
    local origin = vec2(0.0, 0.0)

    if alignX == 'L' then
        origin = vec2(safeMin.x, origin.y)
    elseif alignX == 'R' then
        origin = vec2(safeMax.x - size.x, origin.y)
    elseif alignX == 'C' then
        local centerX = (safeMin.x + safeMax.x - size.x) * 0.5
        origin = vec2(centerX, origin.y)
    end

    if alignY == 'T' then
        origin = vec2(origin.x, safeMin.y)
    elseif alignY == 'B' then
        origin = vec2(origin.x, safeMax.y - size.y)
    elseif alignY == 'C' then
        local centerY = (safeMin.y + safeMax.y - size.y) * 0.5
        origin = vec2(origin.x, centerY)
    end

    return vec2(origin.x + offset.x, origin.y + offset.y)
end

function GetAnchorScreenCoords(alignX, alignY, x, y, w, h)
    local component = {}

    local _cv, _cs = AdjustNormalized16_9ValuesForCurrentAspectRatio(alignX, x, y, w, h, true)
    local cv = CalculateHudPosition(_cv, _cs, alignX, alignY)

    component.Width = _cs.x
    component.Height = _cs.y
    component.LeftX = cv.x
    component.TopY = cv.y
    component.RightX = cv.x + component.Width
    component.BottomY = cv.y + component.Height
    component.CenterX = component.LeftX + (component.Width * 0.5)
    component.CenterY = component.TopY + (component.Height * 0.5)
    component.x = component.LeftX
    component.y = component.TopY

    return component
end

function ConvertScreenCoordsToResolutionCoords(nx, ny)
    local w, h = GetActualScreenResolution()
    return vec2(math.floor(nx * w + 0.5), math.floor(ny * h + 0.5))
end

