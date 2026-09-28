local screenshakeEnabled = false
local recoilEnabled = false

local RECOIL_DURATION = 0.15
local RECOIL_PITCH_STEP = 0.1
local PUNCH_BLOCK_DURATION = 1500

local EXEMPT_WEAPONS = {
    [`WEAPON_STUNGUN`] = true,
    [`WEAPON_PAINTBALL`] = true,
}

local shakeTypes = {
    'HAND_SHAKE',
    'CINEMATIC_SHOOTING_RUN_SHAKE',
    'WATER_BOB_SHAKE',
}

local isCameraShaking = false
local wasAiming = false
local currentShakeType = 'HAND_SHAKE'
local previousShakeType = 'HAND_SHAKE'
local isAimPunchBlocked = false
local wasPlayerAiming = false

local isRecoilThreadActive = false
local isScreenshakeThreadActive = false

local function stopScreenshake()
    if isCameraShaking then
        StopGameplayCamShaking(true)
        isCameraShaking = false
    end

    wasAiming = false
end

---@return string
local function getRandomShakeType()
    return shakeTypes[math.random(1, #shakeTypes)]
end

---@return boolean
local function isPlayerAiming()
    local ped = cache.ped

    return IsControlPressed(0, 25)
        or IsAimCamActive()
        or GetPedConfigFlag(ped, 78, true)
end

local function applyRecoil()
    local startTime = GetGameTimer()

    while (GetGameTimer() - startTime) / 1000.0 < RECOIL_DURATION do
        if not recoilEnabled then
            return
        end

        SetGameplayCamRelativePitch(GetGameplayCamRelativePitch() + RECOIL_PITCH_STEP, 0.2)
        Wait(0)
    end
end

local function startRecoilThread()
    if isRecoilThreadActive then
        return
    end

    isRecoilThreadActive = true

    CreateThread(function()
        while recoilEnabled do
            if IsPedShooting(cache.ped) then
                applyRecoil()
            else
                Wait(0)
            end
        end

        isRecoilThreadActive = false
    end)
end

local function tickScreenshake()
    if IsPedDeadOrDying(cache.ped, true) then
        if isCameraShaking then
            stopScreenshake()
        end

        return
    end

    local ped = cache.ped
    local aiming = isPlayerAiming()
    local currentWeapon = GetSelectedPedWeapon(ped)
    local isInVehicle = IsPedInAnyVehicle(ped, false)

    if isInVehicle and GetFollowVehicleCamViewMode() == 4 then
        SetFollowVehicleCamViewMode(1)
    end

    if EXEMPT_WEAPONS[currentWeapon] then
        if isCameraShaking then
            stopScreenshake()
        end
    elseif aiming then
        if not wasAiming then
            wasAiming = true
            currentShakeType = getRandomShakeType()
            previousShakeType = currentShakeType

            local baseIntensity = 2.0
            if isInVehicle then
                baseIntensity = baseIntensity + 0.5
            end

            ShakeGameplayCam(currentShakeType, baseIntensity)
            isCameraShaking = true
        elseif isCameraShaking and currentShakeType ~= previousShakeType then
            local baseIntensity = 1.0
            if isInVehicle then
                baseIntensity = baseIntensity + 0.5
            end

            ShakeGameplayCam(currentShakeType, baseIntensity)
            previousShakeType = currentShakeType
        elseif wasAiming and not IsGameplayCamShaking() then
            local baseIntensity = 2.0
            if isInVehicle then
                baseIntensity = baseIntensity + 0.5
            end

            ShakeGameplayCam(currentShakeType, baseIntensity)
            isCameraShaking = true
        end
    elseif wasAiming then
        stopScreenshake()
    end
end

local function tickAimPunchBlock()
    local aiming = IsControlPressed(0, 25)

    if wasPlayerAiming and not aiming and not isAimPunchBlocked then
        isAimPunchBlocked = true

        CreateThread(function()
            local endTime = GetGameTimer() + PUNCH_BLOCK_DURATION

            while GetGameTimer() < endTime and screenshakeEnabled do
                DisableControlAction(0, 25, true)
                Wait(0)
            end

            isAimPunchBlocked = false
        end)
    end

    if isAimPunchBlocked then
        DisableControlAction(0, 25, true)
    end

    wasPlayerAiming = aiming
end

local function startScreenshakeThread()
    if isScreenshakeThreadActive then
        return
    end

    isScreenshakeThreadActive = true
    wasPlayerAiming = IsControlPressed(0, 25)

    CreateThread(function()
        while screenshakeEnabled do
            tickScreenshake()
            tickAimPunchBlock()
            Wait(0)
        end

        isScreenshakeThreadActive = false
    end)
end

---@param enabled boolean
local function setScreenshakeEnabled(enabled)
    screenshakeEnabled = enabled == true

    if screenshakeEnabled then
        startScreenshakeThread()
    else
        stopScreenshake()
        isAimPunchBlocked = false
    end
end

exports('setWindyScreenshake', setScreenshakeEnabled)

---@param enabled boolean
local function setRecoilEnabled(enabled)
    recoilEnabled = enabled == true

    if recoilEnabled then
        startRecoilThread()
    end
end

exports('setWindyRecoil', setRecoilEnabled)

local function clearWindyEffects()
    setScreenshakeEnabled(false)
    setRecoilEnabled(false)
end

exports('clearWindyEffects', clearWindyEffects)

exports('isWindyScreenshakeEnabled', function()
    return screenshakeEnabled
end)

exports('isWindyRecoilEnabled', function()
    return recoilEnabled
end)
