---Miscellaneous client-side world dressing.
---
---Every folder beside this file is one self-contained thing: its config.lua
---is the data, and the matching section below is the behaviour. They share
---this file rather than one script each because the manifest loads a single
---client script, and because almost all of them are the same shape -- a
---render loop that only does work while the local player is near something.
---
---The distance gate is the point. Spawn is small and busy, so nothing here
---draws, streams or spawns until the player is close enough to see it.

local config = {
    bloodfx = require 'bloodfx.config',
    disableservices = require 'disableservices.config',
    hitmarkers = require 'hitmarkers.config',
    killEffects = require 'killeffects.config',
    pads = require 'pads.config',
    peds = require 'peds.config',
    portalsText = require 'portals-text.config',
    spawnText = require 'spawntext.config',
    top3 = require 'top3.config',
}

local ui = exports.ui

-- --------------------------------------------------------------- drawing ----

---Default distance at which a text entry starts drawing, when its config row
---does not name one.
local DEFAULT_TEXT_DISTANCE = 15.0

---@param coords vector3
---@param lines string[]
---@param size number
local function drawLines(coords, lines, size)
    -- Draw origin is set once and the lines are stacked in screen space, so a
    -- multi-line sign stays readable from an angle instead of skewing with
    -- the world.
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)

    for index = 1, #lines do
        SetTextScale(0.0, size * 4.0)
        SetTextFont(4)
        SetTextCentre(true)
        SetTextColour(255, 255, 255, 215)
        SetTextOutline()
        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName(lines[index])
        EndTextCommandDisplayText(0.0, (index - 1) * (size * 2.2))
    end

    ClearDrawOrigin()
end

---Seconds until `timestamp`, as the sign renders it.
---@param timestamp integer unix seconds
---@return string?
local function formatCountdown(timestamp)
    local remaining = timestamp - GetCloudTimeAsInt()

    if remaining <= 0 then
        return nil
    end

    local days = math.floor(remaining / 86400)
    local hours = math.floor((remaining % 86400) / 3600)
    local minutes = math.floor((remaining % 3600) / 60)
    local seconds = remaining % 60

    if days > 0 then
        return ('%dd %02dh %02dm'):format(days, hours, minutes)
    end

    return ('%02dh %02dm %02ds'):format(hours, minutes, seconds)
end

-- ------------------------------------------------------- disable services ---

---Dispatch, cops and the wanted level, all off. Re-applied on a slow loop
---because a respawn, a session transition or another resource can quietly
---hand any of it back.
CreateThread(function()
    while true do
        local playerId = PlayerId()

        ClearPlayerWantedLevel(playerId)
        SetMaxWantedLevel(config.disableservices.maxWantedLevel)
        SetPlayerWantedLevel(playerId, 0, false)
        SetPlayerWantedLevelNow(playerId, false)

        for service, enabled in pairs(config.disableservices.enabledServices) do
            EnableDispatchService(service, enabled)
        end

        SetCreateRandomCops(false)
        SetCreateRandomCopsNotOnScenarios(false)
        SetCreateRandomCopsOnScenarios(false)
        SetGarbageTrucks(false)
        SetRandomBoats(false)

        Wait(2000)
    end
end)

-- ------------------------------------------------------------------ peds ----

---@class MiscScenarioPed
---@field model string
---@field coords vector4
---@field renderDistance number
---@field scenario { name: string }?

---@type table<integer, integer> config index -> ped handle
local scenarioPeds = {}

---@param entry MiscScenarioPed
---@return integer?
local function spawnScenarioPed(entry)
    local model = joaat(entry.model)

    if not IsModelInCdimage(model) or not IsModelValid(model) then
        return nil
    end

    lib.requestModel(model, 10000)

    local ped = CreatePed(4, model, entry.coords.x, entry.coords.y, entry.coords.z - 1.0, entry.coords.w, false, false)

    SetModelAsNoLongerNeeded(model)

    if ped == 0 then
        return nil
    end

    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetEntityAsMissionEntity(ped, true, true)

    if entry.scenario then
        TaskStartScenarioInPlace(ped, entry.scenario.name, 0, true)
    end

    return ped
end

---@param index integer
local function despawnScenarioPed(index)
    local ped = scenarioPeds[index]

    if not ped then
        return
    end

    if DoesEntityExist(ped) then
        DeleteEntity(ped)
    end

    scenarioPeds[index] = nil
end

CreateThread(function()
    CoreClient.awaitPlayerLoaded()

    while true do
        local origin = GetEntityCoords(cache.ped)

        for index = 1, #config.peds do
            local entry = config.peds[index]
            local inRange = #(origin - vector3(entry.coords.x, entry.coords.y, entry.coords.z)) <= entry.renderDistance

            if inRange and not scenarioPeds[index] then
                scenarioPeds[index] = spawnScenarioPed(entry)
            elseif not inRange and scenarioPeds[index] then
                despawnScenarioPed(index)
            end
        end

        Wait(1000)
    end
end)

-- ------------------------------------------------------------ spawn text ----

CreateThread(function()
    CoreClient.awaitPlayerLoaded()

    while true do
        local origin = GetEntityCoords(cache.ped)
        local drawn = false

        for index = 1, #config.spawnText do
            local entry = config.spawnText[index]

            if #(origin - entry.coords) <= (entry.distance or DEFAULT_TEXT_DISTANCE) then
                drawLines(entry.coords, entry.lines, entry.size)

                drawn = true
            end
        end

        -- Text has to be issued every frame, but only while something is
        -- actually on screen; away from spawn this loop costs a tick every
        -- half second.
        Wait(drawn and 0 or 500)
    end
end)

-- ---------------------------------------------------------- portals text ----

---@type table<string, integer> portal key -> players inside it
local portalCounts = {}

RegisterNetEvent('core:client:gamemodePortalCounts', function(counts)
    portalCounts = counts or {}
end)

---@param entry table
---@return string[]?
local function buildPortalLines(entry)
    if entry.countdownUntil then
        local countdown = formatCountdown(entry.countdownUntil)

        if not countdown then
            return nil
        end

        return { entry.text or 'Releases In:', ('~r~%s'):format(countdown) }
    end

    if entry.instance then
        local count = portalCounts[entry.instance] or 0

        return { ('%s~r~%d~s~ playing'):format(entry.text and (entry.text .. ' ') or '', count) }
    end

    return entry.text and { entry.text } or nil
end

CreateThread(function()
    CoreClient.awaitPlayerLoaded()

    -- Push-on-change topic, so this subscription costs one message per portal
    -- that actually gains or loses a player.
    TriggerServerEvent('core:server:subscribe', 'gamemodePortalCounts')

    while true do
        local origin = GetEntityCoords(cache.ped)
        local drawn = false

        for index = 1, #config.portalsText do
            local entry = config.portalsText[index]

            if #(origin - entry.coords) <= (entry.distance or DEFAULT_TEXT_DISTANCE) then
                local lines = buildPortalLines(entry)

                if lines then
                    drawLines(entry.coords, lines, entry.size)

                    drawn = true
                end
            end
        end

        Wait(drawn and 0 or 500)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == cache.resource then
        TriggerServerEvent('core:server:unsubscribe', 'gamemodePortalCounts')
    end
end)

-- ------------------------------------------------------------------ pads ----

---How high a plate throws someone, in velocity units.
local PAD_FORCE = 22.0

---Radius around a plate's centre that counts as standing on it.
local PAD_RADIUS = 1.6

---@type integer? GetGameTimer value the current launch stops being ours
local padActiveUntil = nil

local function launch(ped)
    local velocity = GetEntityVelocity(ped)

    SetEntityVelocity(ped, velocity.x, velocity.y, PAD_FORCE)

    padActiveUntil = GetGameTimer() + config.pads.maxDurationMsec

    -- Collision proof, and nothing else: it is what stops the landing killing
    -- them, and leaving bullets and explosions untouched means a pad cannot
    -- be ridden as twenty seconds of immunity. maxDurationMsec is the ceiling
    -- on even that much.
    SetPedCanRagdoll(ped, false)
    SetEntityProofs(ped, false, false, false, true, false, false, false, false)
end

local function endLaunch(ped)
    padActiveUntil = nil

    SetPedCanRagdoll(ped, true)
    SetEntityProofs(ped, false, false, false, false, false, false, false, false)
end

CreateThread(function()
    CoreClient.awaitPlayerLoaded()

    while true do
        local ped = cache.ped
        local origin = GetEntityCoords(ped)
        local near = false

        for index = 1, #config.pads.plates do
            if #(origin - config.pads.plates[index]) <= PAD_RADIUS then
                near = true

                if not padActiveUntil and not IsPedInAnyVehicle(ped, false) then
                    launch(ped)
                end

                break
            end
        end

        if padActiveUntil and (GetGameTimer() >= padActiveUntil or (not near and IsPedOnFoot(ped) and not IsPedFalling(ped) and not IsPedInParachuteFreeFall(ped))) then
            endLaunch(ped)
        end

        Wait(padActiveUntil and 0 or 250)
    end
end)

-- ------------------------------------------------------------------ top3 ----

local podiums = config.top3

local PODIUM_DISTANCE = 20.0
local PODIUM_MODEL = `mp_m_freemode_01`

---@param board table
---@return string
local function podiumKey(board)
    return ('%s:%s'):format(board.category, board.column)
end

---@type table<string, { userId: integer, username: string, value: integer }[]>
local leaderboards = {}

---@type table<string, integer> "<boardKey>:<rank>" -> ped handle
local podiumPeds = {}

---@param board table
---@param rank integer
---@return string
local function podiumPedKey(board, rank)
    return ('%s:%d'):format(podiumKey(board), rank)
end

---@param coords vector4
---@return integer?
local function spawnPodiumPed(coords)
    lib.requestModel(PODIUM_MODEL, 10000)

    local ped = CreatePed(4, PODIUM_MODEL, coords.x, coords.y, coords.z - 1.0, coords.w, false, false)

    SetModelAsNoLongerNeeded(PODIUM_MODEL)

    if ped == 0 then
        return nil
    end

    SetPedRandomComponentVariation(ped, 0)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetEntityAsMissionEntity(ped, true, true)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_MUSCLE_FLEX', 0, true)

    return ped
end

---@param key string
local function despawnPodiumPed(key)
    local ped = podiumPeds[key]

    if not ped then
        return
    end

    if DoesEntityExist(ped) then
        DeleteEntity(ped)
    end

    podiumPeds[key] = nil
end

---Tears every podium ped down. Called when new rows arrive, because a change
---of occupant is a change of ped, not just a change of label.
local function clearPodiumPeds()
    for key in pairs(podiumPeds) do
        despawnPodiumPed(key)
    end
end

RegisterNetEvent('misc:client:leaderboards', function(rows)
    leaderboards = rows or {}

    clearPodiumPeds()
end)

CreateThread(function()
    CoreClient.awaitPlayerLoaded()

    leaderboards = lib.callback.await('misc:server:getLeaderboards', false) or {}

    while true do
        local origin = GetEntityCoords(cache.ped)
        local drawn = false

        for index = 1, #podiums do
            local board = podiums[index]
            local rows = leaderboards[podiumKey(board)] or {}

            for rank = 1, 3 do
                local coords = board.coords[rank]
                local key = podiumPedKey(board, rank)
                local entry = rows[rank]

                if coords and #(origin - vector3(coords.x, coords.y, coords.z)) <= PODIUM_DISTANCE then
                    if entry and not podiumPeds[key] then
                        podiumPeds[key] = spawnPodiumPed(coords)
                    end

                    drawLines(vector3(coords.x, coords.y, coords.z + 1.15), {
                        ('~r~#%d~s~ %s'):format(rank, board.label),
                        entry and entry.username or 'Nobody yet',
                        entry and ('%s: %d'):format(board.column, entry.value) or '-',
                    }, 0.12)

                    drawn = true
                elseif podiumPeds[key] then
                    despawnPodiumPed(key)
                end
            end
        end

        Wait(drawn and 0 or 1000)
    end
end)

-- --------------------------------------------------------------- bloodfx ----

---Particle test area.
---
---A ped that can be shot, standing in front of a menu of every effect in
---bloodfx/config.lua, so impact and blood FX can be compared side by side
---without hunting for a live target.

---@type integer[]
local bloodFxPeds = {}

---@type integer index into config.bloodfx.particleList
local bloodFxSelection = 1

local BLOODFX_MENU = 'misc_bloodfx'

local function clearBloodFxPeds()
    for index = 1, #bloodFxPeds do
        if DoesEntityExist(bloodFxPeds[index]) then
            DeleteEntity(bloodFxPeds[index])
        end
    end

    bloodFxPeds = {}
end

local function spawnBloodFxPeds()
    clearBloodFxPeds()

    for index = 1, #config.bloodfx.pedSpawns do
        local spawn = config.bloodfx.pedSpawns[index]

        lib.requestModel(spawn.modelHash, 10000)

        local ped = CreatePed(4, spawn.modelHash, spawn.position.x, spawn.position.y, spawn.position.z - 1.0, spawn.position.w, false, false)

        SetModelAsNoLongerNeeded(spawn.modelHash)

        if ped ~= 0 then
            SetEntityInvincible(ped, false)
            SetPedCanRagdoll(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetPedDiesWhenInjured(ped, false)
            SetPedSuffersCriticalHits(ped, false)
            SetEntityAsMissionEntity(ped, true, true)

            bloodFxPeds[#bloodFxPeds + 1] = ped
        end
    end
end

---@param particle table
---@param coords vector3
local function playParticle(particle, coords)
    lib.requestNamedPtfxAsset(particle.dictionaryName, 10000)

    UseParticleFxAsset(particle.dictionaryName)
    StartParticleFxNonLoopedAtCoord(particle.clipName, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, particle.scale, false, false, false)
end

local function previewParticle()
    local particle = config.bloodfx.particleList[bloodFxSelection]

    if not particle then
        return
    end

    -- On every test ped if any are up, otherwise in front of the player, so
    -- the menu is still useful before the peds are spawned.
    if #bloodFxPeds == 0 then
        return playParticle(particle, GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 2.0, 0.0))
    end

    for index = 1, #bloodFxPeds do
        if DoesEntityExist(bloodFxPeds[index]) then
            playParticle(particle, GetEntityCoords(bloodFxPeds[index]))
        end
    end
end

WarMenu.CreateMenu(BLOODFX_MENU, 'Blood & Particle FX', 'Developer')

CreateThread(function()
    while true do
        if WarMenu.IsMenuOpened(BLOODFX_MENU) then
            local names = {}

            for index = 1, #config.bloodfx.particleList do
                names[index] = config.bloodfx.particleList[index].name
            end

            local pressed, selection = WarMenu.ComboBox('Effect', names, bloodFxSelection)

            bloodFxSelection = selection or bloodFxSelection

            if pressed then
                previewParticle()
            end

            if WarMenu.Button('Spawn test peds') then
                spawnBloodFxPeds()
            end

            if WarMenu.Button('Remove test peds') then
                clearBloodFxPeds()
            end

            if WarMenu.Button('Teleport to test area') then
                lib.callback.await('misc:server:bloodFxTeleport', false)
            end

            WarMenu.Display()

            Wait(0)
        else
            Wait(250)
        end
    end
end)

RegisterCommand('bloodfx', function()
    if not lib.callback.await('misc:server:canUseBloodFx', false) then
        return ui:notify({ type = 'error', text = 'You do not have permission to do that.' })
    end

    WarMenu.OpenMenu(BLOODFX_MENU)
end, false)

-- ------------------------------------------------- kill effects & markers ---

---Hit feedback and headshot particles.
---
---Both are per-player cosmetic preferences owned by this resource and driven
---entirely from the settings screen (ui/client/uis/settings.lua), which reads
---them through the exports at the bottom of this section. They live in KVP
---rather than on the server because nobody but the local player ever needs to
---know which particle they picked.
---
---The two aliases below are the exact strings the settings NUI sends back;
---they are named here because this resource is what stores them.
---@alias HitMarkerSoundMode 'DISABLED' | 'BODY_ONLY' | 'HEAD_ONLY' | 'ALL'
---@alias HitMarkerDamageType 'DISABLED' | 'SINGLE_COLOR' | 'MULTI_COLOR'

local KVP_KEYS = {
    killEffect = 'fusionrz:kill_effect',
    attackHitSoundMode = 'fusionrz:hit_attack_mode',
    attackHitVolume = 'fusionrz:hit_attack_volume',
    victimHitSoundMode = 'fusionrz:hit_victim_mode',
    victimHitVolume = 'fusionrz:hit_victim_volume',
    markerDamageType = 'fusionrz:hit_marker_type',
}

---@type integer index into config.killEffects, 1 = Off
local killEffect = 1

---@type table
local hitMarkerSettings = {}

---@param value number?
---@return number
local function clampVolume(value)
    return math.min(1.0, math.max(0.0, tonumber(value) or 1.0))
end

do
    local stored = GetResourceKvpInt(KVP_KEYS.killEffect)

    if config.killEffects[stored] then
        killEffect = stored
    end

    local defaults = config.hitmarkers.defaults

    local attackMode = GetResourceKvpString(KVP_KEYS.attackHitSoundMode)
    local victimMode = GetResourceKvpString(KVP_KEYS.victimHitSoundMode)
    local damageType = GetResourceKvpString(KVP_KEYS.markerDamageType)
    local attackVolume = GetResourceKvpFloat(KVP_KEYS.attackHitVolume)
    local victimVolume = GetResourceKvpFloat(KVP_KEYS.victimHitVolume)

    hitMarkerSettings = {
        attackHitSoundMode = config.hitmarkers.soundModes[attackMode] and attackMode or defaults.attackHitSoundMode,
        victimHitSoundMode = config.hitmarkers.soundModes[victimMode] and victimMode or defaults.victimHitSoundMode,
        markerDamageType = config.hitmarkers.damageTypes[damageType] and damageType or defaults.markerDamageType,
        -- A missing float key reads back as 0.0, which is indistinguishable
        -- from a deliberate mute, so an unset volume is taken as the default.
        attackHitVolume = attackVolume > 0.0 and clampVolume(attackVolume) or defaults.attackHitVolume,
        victimHitVolume = victimVolume > 0.0 and clampVolume(victimVolume) or defaults.victimHitVolume,
    }
end

---@param mode string
---@param wasHeadshot boolean
---@return boolean
local function soundModeAllows(mode, wasHeadshot)
    if mode == 'ALL' then
        return true
    end

    if mode == 'HEAD_ONLY' then
        return wasHeadshot
    end

    if mode == 'BODY_ONLY' then
        return not wasHeadshot
    end

    return false
end

---PlaySoundFrontend takes no gain, so the volume is a gate rather than a
---fader: zero is silence, anything else plays at the soundset's own level.
---@param sound { name: string, set: string }
---@param volume number
local function playHitSound(sound, volume)
    if volume <= 0.0 then
        return
    end

    PlaySoundFrontend(-1, sound.name, sound.set, true)
end

---@param coords vector3
local function playKillEffect(coords)
    local effect = config.killEffects[killEffect]

    if not effect or not effect.dictionaryName then
        return
    end

    lib.requestNamedPtfxAsset(effect.dictionaryName, 10000)

    UseParticleFxAsset(effect.dictionaryName)
    StartParticleFxNonLoopedAtCoord(effect.clipName, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, effect.scale or 1.0, false, false, false)
end

---CEventNetworkEntityDamage is the only place both ends of a hit are visible
---at once, so attacker feedback, victim feedback and the headshot particle
---are all decided from the one event.
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then
        return
    end

    local victim = args[1]
    local attacker = args[2]
    local wasFatal = args[4] == 1
    local wasHeadshot = args[10] == 1

    if not DoesEntityExist(victim) or not IsEntityAPed(victim) then
        return
    end

    if attacker == cache.ped and victim ~= cache.ped then
        if soundModeAllows(hitMarkerSettings.attackHitSoundMode, wasHeadshot) then
            playHitSound(wasHeadshot and config.hitmarkers.sounds.head or config.hitmarkers.sounds.body, hitMarkerSettings.attackHitVolume)
        end

        if wasFatal and wasHeadshot then
            playKillEffect(GetEntityCoords(victim))
        end
    elseif victim == cache.ped and attacker ~= cache.ped then
        if soundModeAllows(hitMarkerSettings.victimHitSoundMode, wasHeadshot) then
            playHitSound(config.hitmarkers.sounds.taken, hitMarkerSettings.victimHitVolume)
        end
    end
end)

---The settings screen renders these as a dropdown, so the index doubles as
---the stored value -- see the ordering note in killeffects/config.lua.
---@return { id: string, label: string }[]
exports('getKillEffectOptions', function()
    local options = {}

    for index = 1, #config.killEffects do
        options[index] = {
            id = tostring(index - 1),
            label = config.killEffects[index].label,
        }
    end

    return options
end)

---@return integer
exports('getKillEffect', function()
    return killEffect - 1
end)

---@param index integer?
---@return boolean success
exports('setKillEffect', function(index)
    local selection = (tonumber(index) or 0) + 1

    if not config.killEffects[selection] then
        return false
    end

    killEffect = selection

    SetResourceKvpInt(KVP_KEYS.killEffect, selection)

    return true
end)

---@return table
exports('getHitMarkerSettings', function()
    return hitMarkerSettings
end)

---@param key string
---@param mode HitMarkerSoundMode
---@return boolean success
local function setSoundMode(key, mode)
    if not config.hitmarkers.soundModes[mode] then
        return false
    end

    hitMarkerSettings[key] = mode

    SetResourceKvp(KVP_KEYS[key], mode)

    return true
end

---@param key string
---@param volume number
---@return boolean success
local function setVolume(key, volume)
    local value = clampVolume(volume)

    hitMarkerSettings[key] = value

    SetResourceKvpFloat(KVP_KEYS[key], value)

    return true
end

---@param mode HitMarkerSoundMode
---@return boolean success
exports('changeAttackSoundMode', function(mode)
    return setSoundMode('attackHitSoundMode', mode)
end)

---@param volume number
---@return boolean success
exports('changeAttackSoundVolume', function(volume)
    return setVolume('attackHitVolume', volume)
end)

---@param mode HitMarkerSoundMode
---@return boolean success
exports('changeVictimSoundMode', function(mode)
    return setSoundMode('victimHitSoundMode', mode)
end)

---@param volume number
---@return boolean success
exports('changeVictimSoundVolume', function(volume)
    return setVolume('victimHitVolume', volume)
end)

---@param damageType HitMarkerDamageType
---@return boolean success
exports('changeMarkerDamageType', function(damageType)
    if not config.hitmarkers.damageTypes[damageType] then
        return false
    end

    hitMarkerSettings.markerDamageType = damageType

    SetResourceKvp(KVP_KEYS.markerDamageType, damageType)

    return true
end)

-- ------------------------------------------------------ prestige cutscene ---

---The flourish levels/client/main.lua plays while the server resolves a
---prestige. It returns immediately and runs on its own thread, because the
---caller's very next line is a server callback it must not be held up by --
---the camera work is decoration over a round trip, not a gate on it.

local PRESTIGE_DURATION = 4500
local PRESTIGE_EFFECT = 'HeistCelebPass'

local prestigeRunning = false

exports('startPrestigeCutscene', function()
    if prestigeRunning then
        return false
    end

    prestigeRunning = true

    CreateThread(function()
        local ped = cache.ped
        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)

        local camera = CreateCamWithParams(
            'DEFAULT_SCRIPTED_CAMERA',
            coords.x, coords.y, coords.z + 0.5,
            0.0, 0.0, heading,
            45.0, false, 0
        )

        PointCamAtEntity(camera, ped, 0.0, 0.0, 0.0, true)
        SetCamActive(camera, true)
        RenderScriptCams(true, true, 500, true, true)

        AnimpostfxPlay(PRESTIGE_EFFECT, 0, true)
        PlaySoundFrontend(-1, 'RANK_UP', 'HUD_AWARDS', true)

        local deadline = GetGameTimer() + PRESTIGE_DURATION
        local angle = heading

        while GetGameTimer() < deadline do
            angle += 1.5

            local radians = math.rad(angle)

            SetCamCoord(
                camera,
                coords.x + math.sin(radians) * 3.0,
                coords.y - math.cos(radians) * 3.0,
                coords.z + 0.8
            )

            Wait(0)
        end

        RenderScriptCams(false, true, 500, true, true)
        DestroyCam(camera, false)
        AnimpostfxStop(PRESTIGE_EFFECT)

        prestigeRunning = false
    end)

    return true
end)

-- ------------------------------------------------------------- teardown -----

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then
        return
    end

    for index in pairs(scenarioPeds) do
        despawnScenarioPed(index)
    end

    clearPodiumPeds()
    clearBloodFxPeds()

    -- A restart mid-cutscene would otherwise leave the player looking through
    -- a camera nothing owns any more.
    if prestigeRunning then
        RenderScriptCams(false, false, 0, true, true)
        AnimpostfxStop(PRESTIGE_EFFECT)
    end
end)
