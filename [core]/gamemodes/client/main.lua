local utils = require '@core.modules.utils'
local config = require 'config.client'
local hopoutsClientConfig = require '@hopouts.config.client'
local hopoutsSharedConfig = require '@hopouts.config.shared'
local metadata = require 'shared.metadata'
local gamemodeModes = require 'shared.modes'
local carFights = require 'client.car_fights'

local appearance = exports.appearance
local hopouts = exports.hopouts
local admin = exports.admin
local perks = exports.perks
local core = exports.core
local misc = exports.misc
local ui = exports.ui

local playerState = LocalPlayer.state

local currentPreviewInstanceId = nil
local currentPreviewMode = nil
local previousCoords = nil
local currentCam = nil
local currentGame = nil
local currentFreeroamHopouts = nil
local podiumPeds = {}
local inDeathmatchFromQueue = false

local function setDeathmatchQueueSession(active)
    if inDeathmatchFromQueue == active then
        return
    end

    inDeathmatchFromQueue = active
    ui:setDeathmatchQueueHud(active)

    if not active then
        ui:setReturnToLobbyVisible(false)
    end
end

exports('isInDeathmatchQueue', function()
    return inDeathmatchFromQueue
end)

---@param meta table
local function handleGunDelayedPull(meta)
    if meta.lastEquippedWeapon == 0 then
        return
    end

    local currentTime = GetGameTimer()
    if currentTime - meta.lastEquippedWeapon < hopoutsClientConfig.pullOutGunTimeMsec then
        DisablePlayerFiring(cache.playerId, true)
    else
        meta.lastEquippedWeapon = 0
    end
end

---@param meta table
local function handleMeleeSprint(meta)
    local meleeNameHash = meta.meleeNameHash or (meta.meleeName and joaat(meta.meleeName))
    if not meleeNameHash then
        return
    end

    if cache.weapon == meleeNameHash then
        if not meta.hasSprintModifier then
            SetRunSprintMultiplierForPlayer(cache.playerId, 1.2)
            meta.hasSprintModifier = true
        end
    elseif meta.hasSprintModifier then
        SetRunSprintMultiplierForPlayer(cache.playerId, 1.0)
        meta.hasSprintModifier = false
    end

    if IsPlayerBattleAware(cache.playerId) and GetConvarInt('ranked_disableBattleReset', 0) == 0 then
        SetPedUsingActionMode(cache.ped, false, -1, 'DEFAULT_ACTION')
    end
end

local healthPerTime = 4
local healthDelayInterval = hopoutsClientConfig.medKitTimeMsec * healthPerTime / hopoutsClientConfig.healthPerMedkit

---@type table<string, string>
local defaultItemKeybinds = {
    rifle = '1',
    pistol = '2',
    axe = '3',
    vest = '4',
    medkit = '5',
    blunt = '6',
    repairkit = '7',
    smoke = '8',
}

---@param key 'rifle' | 'pistol' | 'axe' | 'vest' | 'medkit' | 'blunt' | 'repairkit' | 'smoke'
---@return string
local function getItemKeybind(key)
    local currentKey = hopouts:GetItemKeybindKey(key)

    if currentKey and currentKey ~= '' then
        return currentKey
    end

    return defaultItemKeybinds[key] or ''
end

---@param currentAmmo integer?
---@param weaponName string
---@return integer
local function getClipAmmo(currentAmmo, weaponName)
    if not currentAmmo or currentAmmo == -1 then
        return GetMaxAmmoInClip(cache.ped, weaponName, false)
    end

    return currentAmmo
end

---@param meta table
---@return string?
local function getPrimaryWeaponName(meta)
    return meta.primaryName or meta.rifleName
end

---@param meta table
---@return integer
local function getPrimaryClipAmmo(meta)
    return meta.primaryClipAmmo or meta.rifleClipAmmo
end

---@param meta table
---@param clipAmmo integer
local function setPrimaryClipAmmo(meta, clipAmmo)
    meta.primaryClipAmmo = clipAmmo
    meta.rifleClipAmmo = clipAmmo
end

---@param game ClientGamemodeState
---@return 'rifle' | 'pistol'
local function getPrimaryHotbarIcon(game)
    return (game.mode == 'wingman_ffa' or game.mode == 'car_fights_ffa') and 'pistol' or 'rifle'
end

local smokeGrenadeHash = joaat(hopoutsSharedConfig.smokeGrenadeName)

---@param game ClientGamemodeState | FreeroamHopoutsSession
---@param meta table
local function updateHopoutStyleHotbar(game, meta)
    local freeroamHopouts = game.mode == 'freeroam_hopouts'
    local useHopoutsHotbar = freeroamHopouts or game.mode == 'deathmatch'
    local primaryName = getPrimaryWeaponName(meta)
    local meleeName = meta.meleeName

    if not primaryName or not meleeName or (useHopoutsHotbar and not meta.pistolName) then
        return
    end

    local selectedWeapon = GetSelectedPedWeapon(cache.ped)
    local primaryHash = joaat(primaryName)
    local meleeHash = joaat(meleeName)

    local primaryValid, primaryAmmo = GetAmmoInClip(cache.ped, primaryName)
    if primaryValid then
        setPrimaryClipAmmo(meta, primaryAmmo)
    end

    local sendData = {
        rifle = {
            selected = selectedWeapon == primaryHash,
            currentAmmo = getClipAmmo(getPrimaryClipAmmo(meta), primaryName),
            totalAmmo = GetAmmoInPedWeapon(cache.ped, primaryName),
            keybind = getItemKeybind('rifle'),
        },
        axe = {
            selected = selectedWeapon == meleeHash,
            count = 1,
            keybind = getItemKeybind('axe'),
        },
        blunt = {
            count = hopoutsClientConfig.numJoints - (meta.numJointsUsed or 0),
            keybind = getItemKeybind('blunt'),
        },
        medkit = {
            count = hopoutsClientConfig.numMedKitItems - (meta.numMedKitsUsed or 0),
            keybind = getItemKeybind('medkit'),
        },
        vest = {
            count = hopoutsClientConfig.numArmorItems - (meta.numArmorsUsed or 0),
            keybind = getItemKeybind('vest'),
        },
    }

    if useHopoutsHotbar then
        local pistolName = meta.pistolName
        local pistolValid, pistolAmmo = GetAmmoInClip(cache.ped, pistolName)
        if pistolValid then
            meta.pistolClipAmmo = pistolAmmo
        end

        sendData.pistol = {
            selected = selectedWeapon == joaat(pistolName),
            currentAmmo = getClipAmmo(meta.pistolClipAmmo, pistolName),
            totalAmmo = GetAmmoInPedWeapon(cache.ped, pistolName),
            keybind = getItemKeybind('pistol'),
        }

        if freeroamHopouts then
            sendData.repairkit = {
                count = hopoutsClientConfig.numRepairKits,
                keybind = getItemKeybind('repairkit'),
            }
            sendData.smoke = {
                selected = selectedWeapon == smokeGrenadeHash,
                count = hopoutsSharedConfig.smokeGrenadeCount,
                keybind = getItemKeybind('smoke'),
            }
        end
    else
        sendData.primaryIcon = getPrimaryHotbarIcon(game)
    end

    if lib.table.matches(game.lastSentHotbarData, sendData) then
        return
    end

    if useHopoutsHotbar then
        ui:setHopoutsHotbarVisible(true)
        ui:setHopoutsHotbarData(sendData)
    else
        ui:setRifleFfaHotbarData(sendData)
    end

    game.lastSentHotbarData = sendData
end

---@param meta table
local function resetHopoutStyleConsumables(meta)
    meta.lastUsedBlunt = 0
    meta.numJointsUsed = 0
    meta.lastUsedArmor = 0
    meta.numArmorsUsed = 0
    meta.numMedKitsUsed = 0
    meta.healthToGive = 0
    meta.lastGaveHealth = 0
end

---@param meta table
local function refillPrimaryClip(meta)
    setPrimaryClipAmmo(meta, -1)

    local primaryName = getPrimaryWeaponName(meta)
    if not primaryName then
        return
    end

    local primaryHash = joaat(primaryName)
    if not HasPedGotWeapon(cache.ped, primaryHash, false) then
        return
    end

    SetAmmoInClip(cache.ped, primaryHash, GetMaxAmmoInClip(cache.ped, primaryHash, true))
end

---@param meta table
local function refillPistolClip(meta)
    meta.pistolClipAmmo = -1

    local pistolName = meta.pistolName
    if not pistolName then
        return
    end

    local pistolHash = joaat(pistolName)
    if not HasPedGotWeapon(cache.ped, pistolHash, false) then
        return
    end

    SetAmmoInClip(cache.ped, pistolHash, GetMaxAmmoInClip(cache.ped, pistolHash, true))
end

---@param game ClientGamemodeState | FreeroamHopoutsSession
---@param meta table
local function handleItemKeyBinds(game, meta)
    if IsPedShooting(cache.ped) or IsPedReloading(cache.ped) then
        updateHopoutStyleHotbar(game, meta)
    end
end

---@param meta table
local function handleMedKit(meta)
    local currentTime = GetGameTimer()
    if currentTime - meta.lastGaveHealth < healthDelayInterval then
        return
    end

    local healthToGive = math.min(meta.healthToGive, healthPerTime)
    local currentHealth = GetEntityHealth(cache.ped)

    if currentHealth < 200 then
        SetEntityHealth(cache.ped, currentHealth + healthToGive)
    end

    meta.healthToGive -= healthToGive
    meta.lastGaveHealth = currentTime
end

---@param meta table
local function handleItemDurationEffects(meta)
    if meta.healthToGive ~= 0 then
        handleMedKit(meta)
    end
end

---@param meta table
local function handleFirstPersonShooting(meta)
    if currentGame?.mode == 'car_fights_ffa' then
        return
    end

    local isVehicleAiming = cache.vehicle and (IsDisabledControlPressed(0, 24) or IsDisabledControlPressed(0, 25))

    if meta.forceFirstPersonNextFrame then
        if isVehicleAiming then
            if not meta.previousVehicleViewMode then
                meta.previousVehicleViewMode = GetFollowVehicleCamViewMode()
            end

            SetFollowVehicleCamViewMode(4)
        end

        meta.forceFirstPersonNextFrame = false
    end

    if isVehicleAiming then
        if not meta.previousVehicleViewMode then
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 50, true)
            DisableControlAction(0, 68, true)
            DisableControlAction(0, 70, true)
            DisableAimCamThisUpdate()
            meta.forceFirstPersonNextFrame = true
        end
    elseif meta.previousVehicleViewMode then
        SetFollowVehicleCamViewMode(meta.previousVehicleViewMode)
        meta.previousVehicleViewMode = nil
    end
end

---@param weaponName string
---@param meta table
---@param instant boolean
---@param allowVehicle boolean
---@param clipAmmo integer?
local function tryEquipWeapon(weaponName, meta, instant, allowVehicle, clipAmmo)
    if cache.vehicle and not allowVehicle then
        return
    end

    local weaponHash = joaat(weaponName)
    local hasWeapon, currentWeaponHash = GetCurrentPedWeapon(cache.ped)

    if hasWeapon and currentWeaponHash == weaponHash then
        SetCurrentPedWeapon(cache.ped, `WEAPON_UNARMED`, true)
        return
    end

    if not HasPedGotWeapon(cache.ped, weaponHash, false) then
        return
    end

    SetCurrentPedWeapon(cache.ped, weaponHash, true)

    if clipAmmo and clipAmmo >= 0 then
        local ammoBefore = GetAmmoInPedWeapon(cache.ped, weaponHash)
        SetAmmoInClip(cache.ped, weaponHash, clipAmmo)
        SetPedAmmo(cache.ped, weaponHash, ammoBefore)
    end

    if instant then
        return
    end

    lib.requestAnimDict('reaction@intimidation@1h')
    TaskPlayAnim(cache.ped, 'reaction@intimidation@1h', 'intro', 8.0, 8.0, hopoutsClientConfig.pullOutGunTimeMsec // 1.2, 48, 0.0, false, false, false)
    RemoveAnimDict('reaction@intimidation@1h')

    meta.lastEquippedWeapon = GetGameTimer()
end

---@param meta table
local function ensurePrimaryWeaponSelected(meta)
    local primaryName = getPrimaryWeaponName(meta)
    if not primaryName then
        return
    end

    local allowVehicle = currentGame?.mode == 'car_fights_ffa'
    tryEquipWeapon(primaryName, meta, true, allowVehicle, getPrimaryClipAmmo(meta))
end

---@param game ClientGamemodeState
local function initHopoutStyleHotbar(game)
    local meta = game.metadata

    game.lastSentHotbarData = nil
    ensurePrimaryWeaponSelected(meta)
    updateHopoutStyleHotbar(game, meta)
end

AddEventHandler('gamemodes:carFights:vehicleReady', function()
    if not currentGame or currentGame.mode ~= 'car_fights_ffa' then
        return
    end

    initHopoutStyleHotbar(currentGame)
end)

---GTA's own number-key weapon slots (1 = unarmed, 2 = melee, ...). The hotbar
---binds the same keys through hopouts' key mappings, and with these live the
---game swapped weapons in the same frame, undoing every hotbar equip.
local WEAPON_SLOT_CONTROLS = { 157, 158, 159, 160, 161, 162, 163, 164, 165 }

local function disableWeaponWheelThread()
    CreateThread(function()
        while currentGame and gamemodeModes.isHopoutStyleMode(currentGame.mode) do
            HudWeaponWheelIgnoreSelection()
			DisableControlAction(0, 37, true)

            for index = 1, #WEAPON_SLOT_CONTROLS do
                DisableControlAction(0, WEAPON_SLOT_CONTROLS[index], true)
            end

            local meta = currentGame.metadata

            handleGunDelayedPull(meta)
            handleMeleeSprint(meta)
            handleItemDurationEffects(meta)
            handleFirstPersonShooting(meta)
            handleItemKeyBinds(currentGame, meta)

            Wait(0)
        end
    end)
end

---@param serverEndTime number
---@param serverNow number?
---@return number
local function localEndTimeFromServer(serverEndTime, serverNow)
    if type(serverNow) ~= 'number' then
        return serverEndTime
    end

    return GetNetworkTime() + math.max(0, serverEndTime - serverNow)
end

---@param enabled boolean
local function setCayoPericoEnabled(enabled)
    misc:ToggleCayoPerico(enabled)
end

local function destroyCurrentCam()
    if not currentCam then
        return
    end

    if DoesCamExist(currentCam) then
        SetCamActive(currentCam, false)
        DestroyCam(currentCam, true)
    end

    ClearFocus()
    RenderScriptCams(false, false, 0, false, false)

    currentCam = nil
end

---@param hash string | integer
---@param coords vector4
---@param outfit ClothingOutfit?
---@param emoteId? string
---@param anim? { dict: string; name: string }
local function createPodiumPed(hash, coords, outfit, emoteId, anim)
    local model = lib.requestModel(hash)
    local entity = CreatePed(1, model, coords.x, coords.y, coords.z, coords.w, false, true)
    SetModelAsNoLongerNeeded(model)

    lib.waitFor(function()
        if DoesEntityExist(entity) then
            return true
        end
    end)

    SetBlockingOfNonTemporaryEvents(entity, true)
    FreezeEntityPosition(entity, true)
    SetEntityInvincible(entity, true)

    if outfit then
        appearance:setPedAppearance(entity, outfit)
    else
        SetPedDefaultComponentVariation(entity)
    end

    if anim then
        if emoteId then
            local emoteData = core:GetEmoteItem(emoteId)
            if emoteData then
                anim = {
                    dict = emoteData.dict,
                    name = emoteData.anim,
                }
            end
        end
        lib.playAnim(entity, anim.dict, anim.name, 8.0, -8.0, -1, 0, 0, false, 0, false)
    end

    return entity
end

local function cleanupPodiumPeds()
    for _, v in pairs(podiumPeds) do
        utils.deleteEntity(v)
    end

    podiumPeds = {}
end

local function suppressGamemodeRoundUi()
    ui:setRifleFfaHotbarVisible(false)
    ui:setHopoutsHotbarVisible(false)
    ui:setFfaMapSelectVisible(false)
    ui:setFfaWinnersVisible(false)
    ui:setFfaStatsVisible(false)
    ui:setCountdownValue(0)
end

---@param visible boolean
---@param hopoutStyleMode? boolean
local function setFfaLiveRoundUiVisible(visible, hopoutStyleMode)
    ui:setFfaStatsVisible(visible)

    if visible then
        local showHotbar = hopoutStyleMode

        if showHotbar == nil and currentGame then
            showHotbar = gamemodeModes.isHopoutStyleMode(currentGame.mode)
        end

        if showHotbar and (not currentGame or currentGame.mode ~= 'deathmatch') then
            ui:setRifleFfaHotbarVisible(true)
        end
    else
        ui:setRifleFfaHotbarVisible(false)
        ui:setHopoutsHotbarVisible(false)
    end
end

local function restoreAfterLeaveMidFlow()
    suppressGamemodeRoundUi()
    cleanupPodiumPeds()
    destroyCurrentCam()
    setCayoPericoEnabled(false)

    if IsScreenFadedOut() then
        DoScreenFadeIn(500)
    end
end

---@param visible boolean
local function toggleUisVisibility(visible)
    ui:setVitalsVisible(visible)
    ui:setWatermarkMicVisible(visible)
end

---@param disabled boolean
local function toggleUisDisabled(disabled)
    if disabled then
        ui:disableMenu()
    else
        ui:enableMenu()
    end

    -- should only disable during camera phases
    -- ui:disablePauseMenu(disabled)
end

---@param instanceIdOrMode string
local function enterMode(instanceIdOrMode)
    if currentPreviewInstanceId or currentPreviewMode or currentGame then
        return
    end

    currentPreviewInstanceId = instanceIdOrMode

    CreateThread(function()
        while currentPreviewInstanceId do
            DisableAllControlActions(0)
            DisablePlayerFiring(cache.playerId, true)

            Wait(0)
        end
    end)

    toggleUisVisibility(false)
    toggleUisDisabled(true)
    DoScreenFadeOut(0)
    Wait(500)

    local previewData, err = lib.callback.await('gamemodes:server:enterPreview', false, instanceIdOrMode)

    if not previewData then
        lib.print.error(('Unable to enter preview for gamemode: %s. Error: %s'):format(instanceIdOrMode, err))

        currentPreviewInstanceId = nil
        currentPreviewMode = nil

        DoScreenFadeIn(0)
        toggleUisDisabled(false)
        toggleUisVisibility(true)

        ui:notify({ type = 'error', text = err, duration = 5000 })

        TriggerEvent('gamemodes:exitPreview')
        return
    end

    local mode = previewData.mode
    local previewCoords = previewData.coords

    currentPreviewMode = mode
    currentPreviewInstanceId = previewData.instanceId or instanceIdOrMode

    setCayoPericoEnabled(previewData.isCayoIsland)

    local coords, heading = GetEntityCoords(cache.ped), GetEntityHeading(cache.ped)
    previousCoords = vec4(coords.x, coords.y, coords.z, heading)

    SetEntityInvincible(cache.ped, true)
    SetEntityVisible(cache.ped, false, false)

    core:TeleportToCoords(previewCoords)

    if not IsEntityPositionFrozen(cache.ped) then
        FreezeEntityPosition(cache.ped, true)
    end

    destroyCurrentCam()

    currentCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

    local cx, cy, cz = previewCoords.x, previewCoords.y, previewCoords.z
    SetCamCoord(currentCam, cx, cy, cz)

    local rad = math.rad(previewCoords.w)
    local lookAhead = 40.0
    PointCamAtCoord(currentCam, cx - math.sin(rad) * lookAhead, cy + math.cos(rad) * lookAhead, cz)

    RenderScriptCams(true, false, 0, true, false)

    SetFocusPosAndVel(previewCoords.x, previewCoords.y, previewCoords.z, 0.0, 0.0, 0.0)

    -- The NUI renders previewData.tips unguarded, so a mode without an entry
    -- in config/client.lua (deathmatch has none) threw inside React and took
    -- the whole UI down. Fall back to a bare card instead.
    local preview = config.previewData[mode] or {}

    ui:setGamemodePreviewData({
        title = preview.title or mode:gsub('_', ' '):upper(),
        desc = preview.desc or '',
        tips = type(preview.tips) == 'table' and preview.tips or {
            '- Use the pause menu to return to lobby at any time',
        },
    })
    ui:setGamemodePreviewVisible(true)

    DoScreenFadeIn(500)
end

exports('enterMode', enterMode)

---@param data EnterGameData
---@param isExistingPlayer? boolean
local function enterGame(data, isExistingPlayer)
    if NetworkIsInTutorialSession() then
        NetworkEndTutorialSession()
    end

    local isHopoutStyleMode = gamemodeModes.isHopoutStyleMode(data.mode)

    currentGame = {
        gameEndTime = (type(data.gameEndTime) == 'number' and type(data.gameEndServerNow) == 'number') and localEndTimeFromServer(data.gameEndTime, data.gameEndServerNow) or data.gameEndTime,
        phase = isExistingPlayer and 'starting' or 'in_game',
        mode = data.mode,
        metadata = isHopoutStyleMode and metadata.newClient(data.metadata) or {},
    }

    playerState.criticalHits = not isHopoutStyleMode
    playerState.useNativeHeadDamage = isHopoutStyleMode
    GlobalState.disableKillfeed = true

    perks:setReviveDisabled(true)
    admin:setNoClipDisabled(true)
    ui:setPauseMenuDisablePreview(true)
    ui:setPauseMenuDisableProfile(true)
    setDeathmatchQueueSession(data.mode == 'deathmatch')

    if isHopoutStyleMode then
        hopouts:SetupDamageModifiers(false)

        misc:setDamageTextVisible(true)
        misc:DisableBlindFiring(true)
        misc:SetCanCrouch(true)

        perks:setHealthDisabled(true)
        perks:setArmorDisabled(true)

        disableWeaponWheelThread()
    end

    previousCoords = nil

    if not isExistingPlayer then
        DoScreenFadeOut(0)
        ui:setGamemodePreviewVisible(false)
    end

    setCayoPericoEnabled(data.isCayoIsland == true)

    destroyCurrentCam()

    if data.mode == 'car_fights_ffa' then
        if data.spawnCoords then
            FreezeEntityPosition(cache.ped, false)
            SetEntityCoords(cache.ped, data.spawnCoords.x, data.spawnCoords.y, data.spawnCoords.z, false, false, false, false)
            SetEntityHeading(cache.ped, data.spawnCoords.w)
        end
    else
        core:TeleportToCoords(data.spawnCoords)
    end

    if isHopoutStyleMode and data.mode == 'car_fights_ffa' then
        carFights.start(data.vehicleNetId)
    end

    if isExistingPlayer and type(data.countdownRemainingMs) == 'number' then
        SetEntityInvincible(cache.ped, true)
        SetEntityVisible(cache.ped, false, false)

        local freezeForCountdown = data.freezeDuringCountdown ~= false
        if freezeForCountdown then
            FreezeEntityPosition(cache.ped, true)
        end

        currentGame.pendingRoundLiveRelease = {
            freezeDuringCountdown = freezeForCountdown,
        }

        DoScreenFadeIn(1000)

        toggleUisVisibility(true)
        SetEntityVisible(cache.ped, true, true)

        CreateThread(function()
            Wait(500)

            SetGameplayCamRelativePitch(0.0, 1.0)
            SetGameplayCamRelativeHeading(0.0)
        end)

        local countdownEndsAt = GetNetworkTime() + math.max(0, data.countdownRemainingMs)

        CreateThread(function()
            while currentGame and currentGame.phase == 'starting' and GetNetworkTime() < countdownEndsAt do
                local remainingMs = countdownEndsAt - GetNetworkTime()
                local sec = math.max(0, math.ceil(remainingMs / 1000))

                ui:setCountdownValue(sec)
                Wait(100)
            end

            if currentGame and currentGame.phase == 'starting' then
                ui:setCountdownValue(0)
            end
        end)

        CreateThread(function()
            while currentGame and currentGame.phase == 'starting' do
                DisableAllControlActions(0)
                DisablePlayerFiring(cache.playerId, true)

                if freezeForCountdown and not IsEntityPositionFrozen(cache.ped) then
                    FreezeEntityPosition(cache.ped, true)
                end

                if currentGame.mode == 'car_fights_ffa' and cache.vehicle and not IsEntityPositionFrozen(cache.vehicle) then
                    FreezeEntityPosition(cache.vehicle, true)
                end

                Wait(0)
            end
        end)
    else
        -- enterMode froze the ped for the preview camera. The countdown branch
        -- above hands the release to roundLive, but a player dropping straight
        -- into a live round has nothing else that would ever unfreeze them.
        FreezeEntityPosition(cache.ped, false)
        SetEntityVisible(cache.ped, true, true)
        SetEntityInvincible(cache.ped, false)
        DoScreenFadeIn(1000)
    end

    if not currentGame then
        return
    end

    if data.statsValue and data.statsMaxValue then
        ui:setFfaStatsValue(data.statsValue)
        ui:setFfaStatsMaxValue(data.statsMaxValue)
    end

    ui:setFfaStatsPlayers(data.top3 or {})

    if currentGame.gameEndTime then
        CreateThread(function()
            while currentGame do
                if currentGame.gameEndTime then
                    local remainingMs = currentGame.gameEndTime - GetNetworkTime()
                    local remainingSec = math.max(0, math.floor(remainingMs / 1000))

                    ui:setFfaStatsTime(remainingSec)
                end

                Wait(500)
            end
        end)
    else
        ui:setFfaStatsTime(false)
    end

    setFfaLiveRoundUiVisible(true, isHopoutStyleMode)

    if not isExistingPlayer then
        toggleUisVisibility(true)
    end

    if isHopoutStyleMode then
        CreateThread(function()
            lib.waitFor(function()
                if not currentGame then
                    return true
                end

                local primaryName = getPrimaryWeaponName(currentGame.metadata)

                if not primaryName then
                    return false
                end

                return HasPedGotWeapon(cache.ped, joaat(primaryName), false)
            end, 'hopout style weapons', 5000)

            if currentGame and gamemodeModes.isHopoutStyleMode(currentGame.mode) then
                initHopoutStyleHotbar(currentGame)
            end
        end)
    end
end

---@param instanceIdOrMode string
---@return boolean
---@return string?
local function enterModeImmediate(instanceIdOrMode)
    if currentPreviewInstanceId or currentPreviewMode or currentGame then
        return false, 'Already in a gamemode'
    end

    currentPreviewInstanceId = instanceIdOrMode

    toggleUisVisibility(false)
    toggleUisDisabled(true)
    DoScreenFadeOut(0)
    Wait(500)

    local previewData, err = lib.callback.await('gamemodes:server:enterPreview', false, instanceIdOrMode)

    if not previewData then
        currentPreviewInstanceId = nil
        currentPreviewMode = nil

        DoScreenFadeIn(0)
        toggleUisDisabled(false)
        toggleUisVisibility(true)

        return false, err
    end

    currentPreviewMode = previewData.mode
    currentPreviewInstanceId = previewData.instanceId or instanceIdOrMode

    setCayoPericoEnabled(previewData.isCayoIsland)

    local data, enterErr = lib.callback.await('gamemodes:server:enterMode', false, currentPreviewInstanceId)

    if not data then
        TriggerServerEvent('gamemodes:server:exitPreview')

        currentPreviewInstanceId = nil
        currentPreviewMode = nil

        DoScreenFadeIn(0)
        toggleUisDisabled(false)
        toggleUisVisibility(true)

        return false, enterErr
    end

    enterGame(data)

    currentPreviewInstanceId = nil
    currentPreviewMode = nil

    return true
end

exports('enterModeImmediate', enterModeImmediate)

AddEventHandler('uis:enterGamemode', function()
    if not currentPreviewInstanceId then
        return
    end

    local data, err = lib.callback.await('gamemodes:server:enterMode', false, currentPreviewInstanceId)

    if not data then
        lib.print.error(('Unable to enter gamemode: %s. Error: %s'):format(currentPreviewInstanceId, err))
        ui:notify({ type = 'error', text = err, duration = 5000 })

        return
    end

    enterGame(data)

    currentPreviewInstanceId = nil
    currentPreviewMode = nil
end)

AddEventHandler('uis:closeGamemodePreview', function()
    if not currentPreviewInstanceId then
        return
    end

    DoScreenFadeOut(500)
    Wait(500)

    destroyCurrentCam()

    ui:setGamemodePreviewVisible(false)

    setCayoPericoEnabled(false)

    if previousCoords then
        core:TeleportToCoords(previousCoords)
    end

    SetEntityVisible(cache.ped, true, true)
    SetEntityInvincible(cache.ped, false)

    TriggerEvent('gamemodes:exitPreview')
    TriggerServerEvent('gamemodes:server:exitPreview')

    DoScreenFadeIn(500)

    toggleUisVisibility(true)
    toggleUisDisabled(false)

    currentPreviewInstanceId = nil
    currentPreviewMode = nil
end)

---@param maxArmor? integer
RegisterNetEvent('gamemodes:applyKillSiphon', function(maxArmor)
    if not currentGame or currentGame.phase ~= 'in_game' then
        return
    end

    maxArmor = maxArmor or 100

    local health = GetEntityHealth(cache.ped)
    local maxHealth = GetEntityMaxHealth(cache.ped)
    local armor = GetPedArmour(cache.ped)
    local siphon = 50

    local roomForHealth = maxHealth - health
    local toHealth = math.min(siphon, math.max(0, roomForHealth))
    local toArmor = siphon - toHealth

    if toHealth > 0 then
        SetEntityHealth(cache.ped, health + toHealth)
    end

    if toArmor > 0 then
        SetPedArmour(cache.ped, math.min(maxArmor, armor + toArmor))
    end

    if cache.weapon then
        SetAmmoInClip(cache.ped, cache.weapon, GetMaxAmmoInClip(cache.ped, cache.weapon, true))
    end
end)

---@param value string
---@param maxValue string
RegisterNetEvent('gamemodes:statsUpdated', function(value, maxValue)
    if not currentGame or currentGame.phase ~= 'in_game' then
        return
    end

    ui:setFfaStatsValue(value)
    ui:setFfaStatsMaxValue(maxValue)
end)

---GTA weapon groups -> the kill feed's icon set, which draws 'pistol' and
---'rifle' (and 'suicide' for a death with no killer). Sidearms and melee take
---the pistol icon; every long gun, and anything unrecognised, the rifle.
local PISTOL_GROUPS = {
    [`GROUP_PISTOL`] = true,
    [`GROUP_STUNGUN`] = true,
    [`GROUP_MELEE`] = true,
    [`GROUP_UNARMED`] = true,
}

---@param weaponHash integer?
---@return 'pistol' | 'rifle'
local function killfeedWeaponType(weaponHash)
    if not weaponHash or weaponHash == 0 then
        return 'rifle'
    end

    return PISTOL_GROUPS[GetWeapontypeGroup(weaponHash)] and 'pistol' or 'rifle'
end

---@param entry GamemodeKillfeedEntry
RegisterNetEvent('gamemodes:playerKilled', function(entry)
    local weaponType = entry.weaponType == 'suicide' and 'suicide' or killfeedWeaponType(entry.weaponHash)

    ui:addKillfeed({
        isHeadshot = entry.isHeadshot == true,
        shouldHighlight = cache.serverId == entry.killerSrc or cache.serverId == entry.victimSrc,
        weaponType = weaponType,
        killer = entry.killer,
        victim = entry.victim,
    })

    if cache.serverId == entry.killerSrc then
        ui:addKillNoti({ username = entry.victim.username })
    end
end)

---@param top3 table
RegisterNetEvent('gamemodes:top3Updated', function(top3)
    if currentGame?.phase ~= 'in_game' then return end

    ui:setFfaStatsPlayers(top3)
end)

---@param winners table
RegisterNetEvent('gamemodes:matchEnded', function(winners)
    if not currentGame or currentGame.phase ~= 'in_game' then
        return
    end

    carFights.stop()

    currentGame = {
        phase = 'podium',
    }

    CreateThread(function()
        while currentGame and currentGame.phase ~= 'in_game' do
            DisableAllControlActions(0)
            Wait(0)
        end
    end)

    toggleUisVisibility(false)
    setFfaLiveRoundUiVisible(false)

    DoScreenFadeOut(1500)
    Wait(1500)

    setCayoPericoEnabled(false)

    if not currentGame then
        restoreAfterLeaveMidFlow()
        return
    end
    if currentGame.phase ~= 'podium' then
        return
    end

    if not NetworkIsInTutorialSession() then
        NetworkStartSoloTutorialSession()
    end

    while not NetworkIsInTutorialSession() do
        Wait(0)
        if not currentGame then
            restoreAfterLeaveMidFlow()
            return
        end
        if currentGame.phase ~= 'podium' then
            return
        end
    end

    if not currentGame then
        restoreAfterLeaveMidFlow()
        return
    end
    if currentGame.phase ~= 'podium' then
        return
    end

    SetEntityVisible(cache.ped, false, false)
    SetEntityInvincible(cache.ped, true)

    core:TeleportToCoords(vec4(config.winnersPodiumCam.x, config.winnersPodiumCam.y, config.winnersPodiumCam.z + 15.0, config.winnersPodiumCam.w))

    if not IsEntityPositionFrozen(cache.ped) then
        FreezeEntityPosition(cache.ped, true)
    end

    destroyCurrentCam()

    currentCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', config.winnersPodiumCam.x, config.winnersPodiumCam.y, config.winnersPodiumCam.z, 0.0, 0.0, config.winnersPodiumCam.w, 70.0, true, 0)

    RenderScriptCams(true, false, 0, true, false)

    SetFocusPosAndVel(config.winnersPodiumCam.x, config.winnersPodiumCam.y, config.winnersPodiumCam.z, 0.0, 0.0, 0.0)

    local fallbackModel = 'mp_m_freemode_01'

    if winners.first then
        podiumPeds.first = createPodiumPed(winners.first.outfit?.model or fallbackModel, config.winnersPositions.first, winners.first.outfit, winners.first.emoteId, { dict = 'amb@world_human_cheering@male_a', name = 'base' })
    end

    if winners.second then
        podiumPeds.second = createPodiumPed(winners.second.outfit?.model or fallbackModel, config.winnersPositions.second, winners.second.outfit, winners.second.emoteId, { dict = 'amb@world_human_strip_watch_stand@male_a@idle_a', name = 'idle_a' })
    end

    if winners.third then
        podiumPeds.third = createPodiumPed(winners.third.outfit?.model or fallbackModel, config.winnersPositions.third, winners.third.outfit, winners.third.emoteId, { dict = 'anim@mp_player_intupperslow_clap', name = 'idle_a' })
    end

    if not currentGame then
        restoreAfterLeaveMidFlow()
        return
    end
    if currentGame.phase ~= 'podium' then
        return
    end

    ui:setFfaWinnersData(winners)
    ui:setFfaWinnersVisible(true)

    DoScreenFadeIn(1500)
end)

---@param data { candidates: table[], endTime: number, endServerNow: number? }
RegisterNetEvent('gamemodes:voteStarted', function(data)
    if not currentGame or currentGame.phase ~= 'podium' then
        return
    end

    setCayoPericoEnabled(false)

    currentGame = {
        phase = 'voting',
        voteEndTime = localEndTimeFromServer(data.endTime, data.endServerNow),
    }

    DoScreenFadeOut(1500)
    Wait(1500)

    if not currentGame then
        restoreAfterLeaveMidFlow()
        return
    end
    if currentGame.phase ~= 'voting' then
        suppressGamemodeRoundUi()
        return
    end

    cleanupPodiumPeds()
    ui:setFfaWinnersVisible(false)

    Wait(1500)

    if not currentGame then
        restoreAfterLeaveMidFlow()
        return
    end
    if currentGame.phase ~= 'voting' then
        suppressGamemodeRoundUi()
        return
    end

    DoScreenFadeIn(1500)

    if not currentGame then
        restoreAfterLeaveMidFlow()
        return
    end
    if currentGame.phase ~= 'voting' then
        suppressGamemodeRoundUi()
        return
    end

    ui:setFfaMapSelectMaps(data.candidates)

    CreateThread(function()
        while currentGame and currentGame.voteEndTime do
            local remainingMs = currentGame.voteEndTime - GetNetworkTime()
            local remainingSec = math.max(0, math.floor(remainingMs / 1000))

            ui:setFfaMapSelectTime(remainingSec)

            if remainingSec <= 0 then
                break
            end

            Wait(500)
        end
    end)

    if not currentGame then
        restoreAfterLeaveMidFlow()
        return
    end
    if currentGame.phase ~= 'voting' then
        suppressGamemodeRoundUi()
        return
    end

    ui:setFfaMapSelectVisible(true)
end)

---@param voteData { map: string, votes: number }
RegisterNetEvent('gamemodes:voteUpdated', function(voteData)
    if not currentGame or currentGame.phase ~= 'voting' then
        return
    end

    ui:setFfaMapSelectVotes(voteData)
end)

RegisterNetEvent('gamemodes:voteEnded', function()
    if not currentGame or (currentGame.phase ~= 'voting' and currentGame.phase ~= 'podium') then
        return
    end

    currentGame = {
        phase = 'transition'
    }

    DoScreenFadeOut(2500)
    ui:setFfaMapSelectVisible(false)
    ui:setFfaWinnersVisible(false)
    cleanupPodiumPeds()
end)

---@param spawnCoords vector4
---@param countdownRemainingMs number
---@param mode? GameMode
---@param statsValue? string
---@param statsMaxValue? string
---@param isCayoIsland? boolean
---@param clientMetadata? table
---@param vehicleNetId? integer
RegisterNetEvent('gamemodes:roundStarting', function(spawnCoords, countdownRemainingMs, mode, statsValue, statsMaxValue, isCayoIsland, clientMetadata, vehicleNetId)
    if currentGame then
        local phase = currentGame.phase

        if phase == 'podium' or phase == 'starting' then
            return
        end

        if phase ~= 'transition' and phase ~= 'voting' and phase ~= 'in_game' then
            return
        end
    end

    enterGame({
        spawnCoords = spawnCoords,
        countdownRemainingMs = countdownRemainingMs,
        mode = mode,
        statsValue = statsValue,
        statsMaxValue = statsMaxValue,
        isCayoIsland = isCayoIsland,
        metadata = clientMetadata,
        freezeDuringCountdown = true,
        vehicleNetId = vehicleNetId,
    }, true)
end)

---@param gameEndTime number
---@param serverTimeAtSend number?
RegisterNetEvent('gamemodes:roundLive', function(gameEndTime, serverTimeAtSend)
    if not currentGame then
        return
    end

    if currentGame.phase == 'in_game' then
        currentGame.gameEndTime = localEndTimeFromServer(gameEndTime, serverTimeAtSend)
        return
    end

    if currentGame.phase ~= 'starting' then
        return
    end

    local pending = currentGame.pendingRoundLiveRelease
    if pending and pending.freezeDuringCountdown then
        FreezeEntityPosition(cache.ped, false)

        if currentGame.mode == 'car_fights_ffa' and cache.vehicle then
            FreezeEntityPosition(cache.vehicle, false)
        end
    end

    currentGame.pendingRoundLiveRelease = nil
    SetEntityInvincible(cache.ped, false)
    ui:setCountdownValue(0)

    currentGame.phase = 'in_game'
    currentGame.gameEndTime = localEndTimeFromServer(gameEndTime, serverTimeAtSend)

    if gamemodeModes.isHopoutStyleMode(currentGame.mode) then
        initHopoutStyleHotbar(currentGame)
    end
end)

-- core resurrects the ped on core:client:revive and raises this once it has.
-- Listening on the net event instead raced core's handler: whichever ran
-- second saw isDead already cleared.
AddEventHandler('core:client:onRevived', function()
    if not currentGame or currentGame.phase ~= 'in_game' or not gamemodeModes.isHopoutStyleMode(currentGame.mode) then
        return
    end

    if ui:progressActive() then
        ui:cancelProgress()
    end

    local game = currentGame
    local meta = game.metadata
    resetHopoutStyleConsumables(meta)

    CreateThread(function()
        Wait(0)

        if currentGame ~= game or game.phase ~= 'in_game' then
            return
        end

        refillPrimaryClip(meta)
        if game.mode == 'deathmatch' then
            refillPistolClip(meta)
        end
        updateHopoutStyleHotbar(game, meta)
    end)
end)

---@param returnToSpawn? boolean
RegisterNetEvent('gamemodes:cleanup', function(returnToSpawn)
    if not currentGame then
        return
    end

    suppressGamemodeRoundUi()

    if ui:progressActive() then
        ui:cancelProgress()
    end

    ui:setPauseMenuDisablePreview(false)
    ui:setPauseMenuDisableProfile(false)
    setDeathmatchQueueSession(false)

    local meta = currentGame.metadata
    local mode = currentGame.mode

    if meta?.hasSprintModifier then
        SetRunSprintMultiplierForPlayer(cache.playerId, 1.0)
    end

    if meta?.previousVehicleViewMode and mode ~= 'car_fights_ffa' then
        SetFollowVehicleCamViewMode(meta.previousVehicleViewMode)
    end

    hopouts:SetupDamageModifiers(true)

    carFights.stop()

    previousCoords = nil
    currentGame = nil

    playerState.criticalHits = true
    playerState.useNativeHeadDamage = false
    GlobalState.disableKillfeed = false

    misc:setDamageTextVisible(false)
    misc:DisableBlindFiring(false)
    misc:SetCanCrouch(false)
    misc:ToggleRecoil(true)

    setCayoPericoEnabled(false)

    if returnToSpawn then
        TriggerEvent('core:client:teleportToSpawn', true)
    end

    if NetworkIsInTutorialSession() then
        NetworkEndTutorialSession()
    end

    destroyCurrentCam()
    cleanupPodiumPeds()

    SetEntityHealth(cache.ped, GetEntityMaxHealth(cache.ped))
    SetPedArmour(cache.ped, 0)

    FreezeEntityPosition(cache.ped, false)
    SetEntityInvincible(cache.ped, false)
    SetEntityVisible(cache.ped, true, true)

    core:reviveSelf(nil, false)

    perks:setHealthDisabled(false)
    perks:setArmorDisabled(false)
    perks:setReviveDisabled(false)

    admin:setNoClipDisabled(false)

    toggleUisVisibility(true)
    toggleUisDisabled(false)
end)

---@param resource string
AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end

    TriggerEvent('gamemodes:cleanup', true)
end)

---@param game ClientGamemodeState | FreeroamHopoutsSession
---@return boolean
local function isGameStillValid(game)
    if game.mode == 'freeroam_hopouts' then
        return currentFreeroamHopouts == game
    end

    return currentGame == game and game.phase == 'in_game'
end

---@param game ClientGamemodeState | FreeroamHopoutsSession
local function isLocalPlayerBusy(game)
    return game.metadata.lastUsedBlunt ~= 0 or game.metadata.lastUsedArmor ~= 0
end

---@param game ClientGamemodeState | FreeroamHopoutsSession
local function useBlunt(game)
    if isLocalPlayerBusy(game) then
        return
    end

    local meta = game.metadata
    local currentArmor = GetPedArmour(cache.ped)

    if currentArmor >= 100 or meta.lastUsedBlunt ~= 0 or meta.numJointsUsed >= hopoutsClientConfig.numJoints then
        return
    end

    if IsPedRagdoll(cache.ped) then
        return
    end

    meta.lastUsedBlunt = GetGameTimer()

    local finished = ui:progressBar({
        duration = hopoutsClientConfig.bluntTimeMsec,
        label = 'Smoking',
        useWhileDead = false,
        canCancel = true,
        allowFalling = true,
        disable = {
            combat = true,
        },
        anim = {
            dict = 'amb@world_human_smoking@male@male_a@enter',
            clip = 'enter',
            flag = 51,
        },
        prop = {
            model = `p_cs_joint_01`,
            bone = 47419,
            pos = vec3(0.015, -0.009, 0.003),
            rot = vec3(55.0, 0.0, 110.0),
        },
    })

    if not isGameStillValid(game) then
        return
    end

    if not finished then
        meta.lastUsedBlunt = 0
        return
    end

    SetPedArmour(cache.ped, math.min(GetPedArmour(cache.ped) + 25, 100))
    meta.lastUsedBlunt = 0

    if not game.infiniteItems then
        meta.numJointsUsed += 1
    end

    updateHopoutStyleHotbar(game, meta)
end

---@param game ClientGamemodeState | FreeroamHopoutsSession
local function useMedKit(game)
    if isLocalPlayerBusy(game) then
        return
    end

    local meta = game.metadata
    local currentHealth = GetEntityHealth(cache.ped)
    if currentHealth >= 200 or meta.healthToGive > 0 or meta.numMedKitsUsed >= hopoutsClientConfig.numMedKitItems then
        return
    end

    lib.requestAnimDict('mp_suicide')
    TaskPlayAnim(cache.ped, 'mp_suicide', 'pill', 2.0, 2.0, 3200, 51, 0, false, false, false)
    RemoveAnimDict('mp_suicide')

    meta.lastGaveHealth = 0
    meta.healthToGive = hopoutsClientConfig.healthPerMedkit

    if not game.infiniteItems then
        meta.numMedKitsUsed += 1
    end

    updateHopoutStyleHotbar(game, meta)
end

---@param game ClientGamemodeState | FreeroamHopoutsSession
local function useArmor(game)
    if isLocalPlayerBusy(game) then
        return
    end

    local meta = game.metadata
    local currentArmor = GetPedArmour(cache.ped)

    if not meta.numArmorsUsed then
        meta.numArmorsUsed = 0
    end

    if currentArmor >= 100 or meta.lastUsedArmor ~= 0 or meta.numArmorsUsed >= hopoutsClientConfig.numArmorItems then
        return
    end

    if IsPedRagdoll(cache.ped) then
        return
    end

    meta.lastUsedArmor = GetGameTimer()

    local finished = ui:progressBar({
        duration = hopoutsClientConfig.armorTimeMsec,
        label = 'Applying Armor',
        useWhileDead = false,
        canCancel = true,
        allowFalling = true,
        disable = {
            combat = true,
        },
        anim = {
            dict = 'missmic4',
            clip = 'michael_tux_fidget',
            flag = 51,
        }
    })

    if not isGameStillValid(game) then
        return
    end

    if not finished then
        meta.lastUsedArmor = 0
        return
    end

    SetPedArmour(cache.ped, 100)
    meta.lastUsedArmor = 0

    if not game.infiniteItems then
        meta.numArmorsUsed += 1
    end

    updateHopoutStyleHotbar(game, meta)
end

---@param session FreeroamHopoutsSession
local function useRepairKit(session)
    local meta = session.metadata

    if meta.repairKitVehicle ~= 0 or IsPedRagdoll(cache.ped) then
        return
    end

    if cache.vehicle then
        return ui:notify({ text = 'You cannot repair while in a vehicle.', type = 'error' })
    end

    local vehicle = lib.getClosestVehicle(GetEntityCoords(cache.ped), hopoutsClientConfig.maxRepairDistance, false)
    if not vehicle then
        return
    end

    meta.repairKitVehicle = vehicle

    local finished = ui:progressBar({
        duration = hopoutsClientConfig.repairKitDurationMsec,
        label = 'Repairing Vehicle',
        useWhileDead = false,
        canCancel = true,
        allowFalling = true,
        disable = {
            combat = true,
            move = true,
            car = true,
        },
        anim = {
            dict = 'missexile3',
            clip = 'ex03_dingy_search_case_base_michael',
            flag = 1 | 16,
        },
    })

    meta.repairKitVehicle = 0

    if not isGameStillValid(session) or not finished or not DoesEntityExist(vehicle) then
        return
    end

    if #(GetEntityCoords(cache.ped) - GetEntityCoords(vehicle)) > hopoutsClientConfig.maxRepairDistance then
        return
    end

    TriggerServerEvent('gamemodes:server:repairFreeroamHopoutsVehicle', NetworkGetNetworkIdFromEntity(vehicle))
end

---@param itemName string
AddEventHandler('hopouts:itemBindPressed', function(itemName)
    if playerState.isDead then
        return
    end

    local session = currentFreeroamHopouts or currentGame

    if not session or (session ~= currentFreeroamHopouts and not gamemodeModes.isHopoutStyleMode(session.mode)) then
        return
    end

    local freeroamHopouts = session == currentFreeroamHopouts
    local meta = session.metadata

    if itemName == 'rifle' then
        local primaryName = getPrimaryWeaponName(meta)
        if primaryName then
            local allowVehicle = session.mode == 'car_fights_ffa' or freeroamHopouts
            tryEquipWeapon(primaryName, meta, true, allowVehicle, getPrimaryClipAmmo(meta))
        end
    elseif itemName == 'pistol' and (freeroamHopouts or session.mode == 'deathmatch') then
        tryEquipWeapon(meta.pistolName, meta, true, freeroamHopouts, meta.pistolClipAmmo)
    elseif itemName == 'melee' then
        tryEquipWeapon(meta.meleeName, meta, true, false)
    elseif itemName == 'smokes' and freeroamHopouts then
        tryEquipWeapon(hopoutsSharedConfig.smokeGrenadeName, meta, true, false)
    elseif itemName == 'blunt' then
        useBlunt(session)
    elseif itemName == 'armor' then
        useArmor(session)
    elseif itemName == 'medkit' then
        useMedKit(session)
    elseif itemName == 'repairkit' and freeroamHopouts then
        useRepairKit(session)
    end

    if freeroamHopouts and currentFreeroamHopouts ~= session then
        return
    end

    updateHopoutStyleHotbar(session, meta)
end)

---@param amount integer
RegisterNetEvent('gamemodes:applyArmor', function(amount)
    if not currentGame or type(amount) ~= 'number' then
        return
    end

    SetPedArmour(cache.ped, amount)
end)

---@param session FreeroamHopoutsSession
local function handleFreeroamHopoutsSmokes(session)
    if GetSelectedPedWeapon(cache.ped) ~= smokeGrenadeHash or not IsPedShooting(cache.ped) then
        session.throwingSmoke = false
    elseif not session.throwingSmoke then
        local pedCoords = GetEntityCoords(cache.ped)
        local object = GetClosestObjectOfType(pedCoords.x, pedCoords.y, pedCoords.z, 10.0, `w_ex_smokegrenade`, false, false, false)

        if object ~= 0 then
            session.throwingSmoke = true

            session.pendingSmokes[#session.pendingSmokes + 1] = {
                timeThrown = GetGameTimer(),
                object = object,
            }
        end
    end

    local currentTime = GetGameTimer()

    for index = 1, #session.pendingSmokes do
        local smokeData = session.pendingSmokes[index]

        if currentTime - smokeData.timeThrown > 3000 or GetEntitySpeed(smokeData.object) < 0.2 then
            TriggerServerEvent('gamemodes:server:createFreeroamHopoutsSmoke', GetEntityCoords(smokeData.object))
            table.remove(session.pendingSmokes, index)
            break
        end
    end
end

---@param session FreeroamHopoutsSession
---@param object integer
---@param fadeIn boolean
local function fadeFreeroamHopoutsSmoke(session, object, fadeIn)
    local startTime = GetGameTimer()

    while currentFreeroamHopouts == session and session.createdSmokes[object] do
        local elapsed = (GetGameTimer() - startTime) / 1000
        local alphaElapsed = fadeIn and elapsed or 1.0 - elapsed

        SetEntityAlpha(object, math.min(math.max(math.round(255 * alphaElapsed), 0), 255), false)

        if elapsed >= 1.0 then
            return
        end

        Wait(0)
    end
end

---@param coords vector3
---@param modelName string
RegisterNetEvent('gamemodes:createFreeroamHopoutsSmoke', function(coords, modelName)
    local session = currentFreeroamHopouts
    if not session then
        return
    end

    local modelHash = lib.requestModel(modelName)

    if currentFreeroamHopouts ~= session then
        SetModelAsNoLongerNeeded(modelHash)
        return
    end

    local object = CreateObjectNoOffset(modelHash, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(modelHash)

    FreezeEntityPosition(object, true)
    SetEntityCollision(object, false, false)
    SetEntityAlpha(object, 0, false)

    session.createdSmokes[object] = true

    fadeFreeroamHopoutsSmoke(session, object, true)
    Wait(15000)
    fadeFreeroamHopoutsSmoke(session, object, false)

    if not session.createdSmokes[object] then
        return
    end

    session.createdSmokes[object] = nil
    DeleteEntity(object)
end)

local freeroamHopoutsWeaponSlotControls = { 157, 158, 160, 164, 165, 159, 161, 162 }

---@param loadout { primaryName: string, pistolName: string, meleeName: string }
local function startFreeroamHopoutsSession(loadout)
    ---@type FreeroamHopoutsSession
    local session = {
        mode = 'freeroam_hopouts',
        infiniteItems = true,
        pendingSmokes = {},
        createdSmokes = {},
        throwingSmoke = false,
        metadata = metadata.newClient({
            rifleName = loadout.primaryName,
            pistolName = loadout.pistolName,
            meleeName = loadout.meleeName,
            pistolClipAmmo = -1,
            repairKitVehicle = 0,
        }),
    }

    currentFreeroamHopouts = session
    misc:SetCanCrouch(true)

    CreateThread(function()
        while currentFreeroamHopouts == session do
            if not IsControlPressed(0, 37) and not IsDisabledControlPressed(0, 37) then
                local slotDown = false

                for i = 1, #freeroamHopoutsWeaponSlotControls do
                    local control = freeroamHopoutsWeaponSlotControls[i]
                    DisableControlAction(0, control, true)
                    if IsDisabledControlPressed(0, control) then
                        slotDown = true
                    end
                end

                if slotDown then
                    HudForceWeaponWheel(false)
                    HudWeaponWheelIgnoreSelection()
                end
            end

            handleFreeroamHopoutsSmokes(session)
            handleGunDelayedPull(session.metadata)
            handleMeleeSprint(session.metadata)
            handleItemDurationEffects(session.metadata)
            handleItemKeyBinds(session, session.metadata)

            Wait(0)
        end
    end)

    updateHopoutStyleHotbar(session, session.metadata)
end

local function stopFreeroamHopoutsSession()
    local session = currentFreeroamHopouts
    if not session then
        return
    end

    currentFreeroamHopouts = nil
    misc:SetCanCrouch(false)

    for index = 1, #session.pendingSmokes do
        DeleteEntity(session.pendingSmokes[index].object)
    end

    for object in pairs(session.createdSmokes) do
        DeleteEntity(object)
    end
    table.wipe(session.createdSmokes)

    if ui:progressActive() then
        ui:cancelProgress()
    end

    ui:setHopoutsHotbarVisible(false)
    TriggerServerEvent('gamemodes:server:clearFreeroamHopoutsLoadout')
end

---@param config { gamemode?: string }?
local function syncFreeroamHopoutsSession(config)
    if type(config) ~= 'table' or config.gamemode ~= 'freeroam_hopouts' then
        stopFreeroamHopoutsSession()
        return
    end

    if currentFreeroamHopouts then
        return
    end

    CreateThread(function()
        local loadout = lib.callback.await('gamemodes:server:freeroamHopoutsLoadout', false)
        if not loadout or currentFreeroamHopouts then
            return
        end

        startFreeroamHopoutsSession(loadout)
    end)
end

RegisterNetEvent('uis:setLobbyConfig', syncFreeroamHopoutsSession)
RegisterNetEvent('uis:leftLobby', stopFreeroamHopoutsSession)
RegisterNetEvent('uis:lobbyDisbanded', stopFreeroamHopoutsSession)

lib.onCache('weapon', function()
    if not currentFreeroamHopouts then
        return
    end

    updateHopoutStyleHotbar(currentFreeroamHopouts, currentFreeroamHopouts.metadata)
end)

---@param vehicleNetId integer
RegisterNetEvent('gamemodes:repairFreeroamHopoutsVehicle', function(vehicleNetId)
    if not NetworkDoesNetworkIdExist(vehicleNetId) or not NetworkDoesEntityExistWithNetworkId(vehicleNetId) then
        return
    end

    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if vehicle == 0 then
        return
    end

    SetVehicleEngineHealth(vehicle, 9999)
    SetVehiclePetrolTankHealth(vehicle, 9999)
    SetVehicleFixed(vehicle)
end)

---@param resource string
AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end

    stopFreeroamHopoutsSession()
end)

---Server-driven respawn. Random spawns (jungle redzone) carry only the area's
---rough height, so after coming back the player is set on the ground there:
---probe just above, then from high up if that finds nothing, and keep the
---original point if the ground never streams in.
---@param coords vector4
RegisterNetEvent('gamemodes:client:respawn', function(coords)
    if type(coords) ~= 'vector4' and type(coords) ~= 'table' then
        return
    end

    core:reviveSelf(coords)

    local ped = PlayerPedId()

    FreezeEntityPosition(ped, true)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)

    local deadline = GetGameTimer() + 2000

    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(0)
    end

    local found, ground = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 3.0, false)

    if not found then
        found, ground = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 50.0, false)
    end

    if found then
        SetEntityCoordsNoOffset(ped, coords.x, coords.y, ground + 1.0, false, false, false)
    end

    SetEntityHeading(ped, coords.w or 0.0)
    FreezeEntityPosition(ped, false)
end)
