local locations = require '@core.data.locations'
local LibDeflate = require '@core.modules.deflate'

local core = exports.core
local ui = exports.ui

local playerState = LocalPlayer.state

local metadata = {}

local VALID_WEATHER = {
    EXTRASUNNY = true,
    CLEAR = true,
    NEUTRAL = true,
    SMOG = true,
    FOGGY = true,
    OVERCAST = true,
    CLOUDS = true,
    CLEARING = true,
    RAIN = true,
    THUNDER = true,
    SNOW = true,
    BLIZZARD = true,
    SNOWLIGHT = true,
    XMAS = true,
    HALLOWEEN = true,
}
---@param key string
---@param value boolean
local function setMetadata(key, value)
    metadata[key] = value
end

---@param key? string
local function clearMetadata(key)
    if key then
        metadata[key] = nil
        return
    end

    metadata = {}
end

local function applyHeadshotState()
    if next(metadata) then
        playerState.criticalHits = not not metadata.headshots
        playerState.useNativeHeadDamage = false
    else
        playerState.criticalHits = true
        playerState.useNativeHeadDamage = false
    end
end

local isQPeakThreadActive = false
local isEnvironmentThreadActive = false

local function applyLobbyEnvironmentValues()
    if type(metadata.weather) == 'string' and VALID_WEATHER[metadata.weather] then
        ui:setWeather(metadata.weather)
    else
        ui:resetWeather()
    end

    if type(metadata.time) == 'number' and metadata.time >= 0 and metadata.time <= 23 then
        ui:setTime(metadata.time)
    else
        ui:resetTime()
    end
end

local function startQPeakThread()
    if isQPeakThreadActive then
        return
    end

    isQPeakThreadActive = true

    CreateThread(function()
        while next(metadata) and not metadata.qPeak do
            DisableControlAction(0, 44, true)
            Wait(0)
        end

        isQPeakThreadActive = false
    end)
end

local function startEnvironmentThread()
    if isEnvironmentThreadActive then
        return
    end

    isEnvironmentThreadActive = true

    CreateThread(function()
        while next(metadata) and (metadata.weather or metadata.time ~= nil) do
            applyLobbyEnvironmentValues()
            Wait(1000)
        end

        isEnvironmentThreadActive = false
    end)
end

local function applyLobbyEnvironment()
    applyLobbyEnvironmentValues()
    startQPeakThread()
    startEnvironmentThread()
end

local function clearLobbyEnvironment()
    ui:resetWeather()
    ui:resetTime()
end

local function applyLobbyWindyEffects()
    if next(metadata) then
        ui:setWindyScreenshake(not not metadata.screenshake)
        ui:setWindyRecoil(not not metadata.recoil)
    else
        ui:clearWindyEffects()
    end
end

local function clearLobbyWindyEffects()
    ui:clearWindyEffects()
end

local function applyLobbyAimCooldown()
    if next(metadata) then
        -- Speedboosting enabled = no cooldown; disabled = anti-speedboost cooldown
        SetAimCooldown(metadata.speedboosting == false and 300 or 0)
    else
        SetAimCooldown(0)
    end
end

local function clearLobbyAimCooldown()
    SetAimCooldown(0)
end

---@param coords vector4
local function teleportIntoLobby(coords)
    if not coords then return end
    ui:disableMenu()
    core:TeleportToCoords(coords, true)
    ui:enableMenu()
end

RegisterNUICallback('getGamemodeMaps', function(data, cb)
    local result = lib.callback.await('uis:server:getGamemodeMaps', false, {
        gamemode = data.gamemode,
        slots = data.slots,
    })
    cb(result or {})
end)

RegisterNUICallback('getFfaMaps', function(data, cb)
    local result = lib.callback.await('uis:server:getFfaMaps', false, {
        gamemode = data.gamemode,
    })
    cb(result or {})
end)

---@param data table
RegisterNUICallback('createLobby', function(data, cb)
    local lobbyMetadata = {
        headshots = data.headshots,
        qPeak = data.qPeak,
        siphon = not not data.siphon,
        screenshake = not not data.screenshake,
        recoil = not not data.recoil,
        instantRevive = not not data.instantRevive,
        speedboosting = data.speedboosting ~= false,
    }

    if type(data.weather) == 'string' and data.weather ~= '' and VALID_WEATHER[data.weather] then
        lobbyMetadata.weather = data.weather
    end

    if type(data.time) == 'number' and data.time >= 0 and data.time <= 23 then
        lobbyMetadata.time = math.floor(data.time)
    end

    local result, err = lib.callback.await('uis:server:createLobby', false, {
        password = data.password,
        slots = data.slots,
        mapId = data.mapId,
        gamemode = data.gamemode or 'freeroam',
        metadata = lobbyMetadata,
        ffaLocationIndex = data.ffaLocationIndex
    })

    if not result then
        lib.print.error('Unable to create lobby:', err)

        return cb({ success = false, error = err })
    end

    cb({ success = true })

    SendNUIMessage({
        action = 'setMyLobbyId',
        data = result.lobbyId
    })

    SendNUIMessage({
        action = 'setLobbyConfig',
        data = {
            password = data.password or '',
            mapId = data.mapId,
            gamemode = data.gamemode or 'freeroam',
            slots = data.slots,
            metadata = lobbyMetadata,
            isOwner = true,
            ffaLocationIndex = data.ffaLocationIndex,
        }
    })

    SendNUIMessage({ action = 'setSelectedPage', data = 'lobbies-members' })

    for k, v in pairs(lobbyMetadata) do
        setMetadata(k, v)
    end

    applyHeadshotState()
    applyLobbyEnvironment()
    applyLobbyWindyEffects()
    applyLobbyAimCooldown()
    teleportIntoLobby(result.coords)
end)

RegisterNUICallback('getWarMaps', function(_, cb)
    cb(lib.callback.await('uis:server:getWarMaps', false))
end)

---@param data { mapId: string, message?: string, teamSize: integer, queensOnly?: boolean }
RegisterNUICallback('createWar', function(data, cb)
    local result, err = lib.callback.await('uis:server:createWar', false, {
        mapId = data.mapId,
        message = data.message,
        teamSize = data.teamSize,
        queensOnly = data.queensOnly == true,
    })

    if not result then
        lib.print.error('Unable to create war:', err)

        return cb({ success = false, error = err })
    end

    cb({ success = true })

    SendNUIMessage({
        action = 'setMyLobbyId',
        data = result.lobbyId
    })

    teleportIntoLobby(result.coords)

    ui:openMenu()

    SendNUIMessage({ action = 'setSelectedPage', data = 'lobbies-members' })
end)

RegisterNUICallback('warStepOut', function(_, cb)
    local success, err = lib.callback.await('uis:server:warStepOut', false)
    cb({ success = success, error = err })
end)

RegisterNUICallback('warStepIn', function(_, cb)
    local success, err = lib.callback.await('uis:server:warStepIn', false)
    cb({ success = success, error = err })
end)

RegisterNUICallback('announceWar', function(_, cb)
    local success, err = lib.callback.await('uis:server:announceWar', false)
    cb({ success = success, error = err })
end)

---@param data { mapId: string }
RegisterNUICallback('setWarMap', function(data, cb)
    local success, err = lib.callback.await('uis:server:setWarMap', false, data.mapId)
    cb({ success = success, error = err })
end)

---@param data { mapIds: string[] }
RegisterNUICallback('startWarMapVote', function(data, cb)
    local success, err = lib.callback.await('uis:server:startWarMapVote', false, data.mapIds)
    cb({ success = success, error = err })
end)

---@param data { mapId: string }
RegisterNUICallback('castWarMapVote', function(data, cb)
    local success, err = lib.callback.await('uis:server:castWarMapVote', false, data.mapId)
    cb({ success = success, error = err })
end)

---@param data { options: string[], counts: table<string, integer>, endsInMsec: integer, myVote: string? }?
RegisterNetEvent('uis:setWarMapVote', function(data)
    SendNUIMessage({ action = 'setWarMapVote', data = data })
end)

RegisterNUICallback('getAllWars', function(_, cb)
    local wars = lib.callback.await('uis:server:getAllWars', false)

    cb(wars)
end)

---@param data { lobbyId: integer }
RegisterNUICallback('spectateWar', function(data, cb)
    local result, err = lib.callback.await('uis:server:spectateWar', false, data.lobbyId)

    if not result then
        ui:notify({ type = 'error', text = err })

        return cb({ success = false, error = err })
    end

    cb({ success = true })

    SendNUIMessage({
        action = 'setMyLobbyId',
        data = result.lobbyId
    })

    ui:closeMenu()
end)

RegisterNUICallback('getAllLobbies', function(_, cb)
    local lobbies = lib.callback.await('uis:server:getAllLobbies', false)

    cb(lobbies)
end)

---@param data { password: string, lobbyId: integer }
RegisterNUICallback('joinLobby', function(data, cb)
    local result, err = lib.callback.await('uis:server:joinLobby', false, data.lobbyId, data.password)

    if not result then
        lib.print.error('Unable to join lobby:', err)

        return cb({ success = false, error = err })
    end

    cb({ success = true })

    SendNUIMessage({
        action = 'setMyLobbyId',
        data = result.lobbyId
    })

    SendNUIMessage({ action = 'setSelectedPage', data = 'lobbies-members' })

    for k, v in pairs(result.metadata or {}) do
        setMetadata(k, v)
    end

    applyHeadshotState()
    applyLobbyEnvironment()
    applyLobbyWindyEffects()
    applyLobbyAimCooldown()
    teleportIntoLobby(result.coords)

    if result.kind == 'war' then
        ui:openMenu()
    end
end)

RegisterNUICallback('deleteMyLobby', function(_, cb)
    local success, err = lib.callback.await('uis:server:deleteMyLobby', false)

    if not success then
        lib.print.error('Unable to delete lobby:', err)

        return cb({ success = false, error = err })
    end

    cb({ success = true })
end)

RegisterNUICallback('leaveLobby', function(_, cb)
    local success, err = lib.callback.await('uis:server:leaveLobby', false)

    if not success then
        lib.print.error('Unable to leave lobby:', err)

        return cb({ success = false, error = err })
    end

    cb({ success = true })

    clearMetadata()
    applyHeadshotState()
    clearLobbyEnvironment()
    clearLobbyWindyEffects()
    clearLobbyAimCooldown()
    TriggerEvent('core:client:teleportToSpawn')
end)

RegisterNetEvent('uis:forceRefreshLobbies', function()
    SendNUIMessage({ action = 'forceRefreshLobbies' })
end)

---@param lobbyId integer
---@param playerCount integer
RegisterNetEvent('uis:lobbyPlayerCountUpdated', function(lobbyId, playerCount)
    SendNUIMessage({
        action = 'lobbyPlayerCountUpdated',
        data = { lobbyId = lobbyId, playerCount = playerCount },
    })
end)

---@param lobbyId integer
RegisterNetEvent('uis:setMyLobbyId', function(lobbyId)
    SendNUIMessage({ action = 'setMyLobbyId', data = lobbyId })
end)

RegisterNetEvent('uis:leftLobby', function()
    SendNUIMessage({ action = 'setMyLobbyId', data = nil })
    clearMetadata()
    applyHeadshotState()
    clearLobbyEnvironment()
    clearLobbyWindyEffects()
    clearLobbyAimCooldown()
end)

---@param players table
RegisterNetEvent('uis:setLobbyPlayers', function(players)
    SendNUIMessage({ action = 'setLobbyPlayers', data = players })
end)

---@param config table
RegisterNetEvent('uis:setLobbyConfig', function(config)
    clearMetadata()

    if type(config.metadata) == 'table' then
        for k, v in pairs(config.metadata) do
            setMetadata(k, v)
        end
    end

    if not config.inGame then
        applyHeadshotState()
        applyLobbyEnvironment()
        applyLobbyWindyEffects()
        applyLobbyAimCooldown()
    end

    startQPeakThread()
    SendNUIMessage({ action = 'setLobbyConfig', data = config })
end)

RegisterNetEvent('uis:teleportLobbyPlayers', function(coords)
    local wasMenuVisible = IsMenuVisible()

    teleportIntoLobby(coords)

    if wasMenuVisible then
        ui:openMenu()
    end
end)

---@param page string
RegisterNetEvent('uis:setSelectedPage', function(page)
    SendNUIMessage({ action = 'setSelectedPage', data = page })
end)

RegisterNUICallback('lobbiesBrowseMounted', function(_, cb)
    TriggerServerEvent('uis:server:lobbiesBrowseOpened')

    cb(1)
end)

RegisterNUICallback('lobbiesBrowseUnmounted', function(_, cb)
    TriggerServerEvent('uis:server:lobbiesBrowseClosed')

    cb(1)
end)

RegisterNUICallback('getLobbyPlayers', function(_, cb)
    local players = lib.callback.await('uis:server:getLobbyPlayers', false)
    cb(players or {})
end)

RegisterNUICallback('restartWarRound', function(_, cb)
    local success, err = lib.callback.await('uis:server:restartWarRound', false)
    if not success then
        return cb({ success = false, error = err })
    end
    cb({ success = true })
end)

RegisterNUICallback('toggleWarFreeze', function(_, cb)
    local success, err = lib.callback.await('uis:server:toggleWarFreeze', false)
    if not success then
        return cb({ success = false, error = err })
    end
    cb({ success = true })
end)

---@param data { userId: integer }
RegisterNUICallback('kickLobbyPlayer', function(data, cb)
    local success, err = lib.callback.await('uis:server:kickLobbyPlayer', false, data)
    if not success then
        lib.print.error('kickLobbyPlayer failed:', err)
        return cb({ success = false, error = err })
    end
    cb({ success = true })
end)

---@param data { userId: integer, team: string|nil }
RegisterNUICallback('setPlayerTeam', function(data, cb)
    local success, err = lib.callback.await('uis:server:setPlayerTeam', false, data)
    if not success then
        lib.print.error('setPlayerTeam failed:', err)
        return cb({ success = false, error = err })
    end
    cb({ success = true })
end)

---@param newSlots integer
RegisterNUICallback('setLobbySlots', function(newSlots, cb)
    local success, err = lib.callback.await('uis:server:setLobbySlots', false, newSlots)
    if not success then
        lib.print.error('setLobbySlots failed:', err)
        return cb({ success = false, error = err })
    end
    cb({ success = true })
end)

---@param data { password?: string, slots: integer, mapId: string, gamemode?: string, headshots?: boolean, qPeak?: boolean, weather?: string|null, time?: number|null, siphon?: boolean, screenshake?: boolean, recoil?: boolean, instantRevive?: boolean, speedboosting?: boolean }
RegisterNUICallback('updateLobbyConfig', function(data, cb)
    local lobbyMetadata = {
        headshots = not not data.headshots,
        qPeak = not not data.qPeak,
        siphon = not not data.siphon,
        screenshake = not not data.screenshake,
        recoil = not not data.recoil,
        instantRevive = not not data.instantRevive,
        speedboosting = data.speedboosting ~= false,
    }

    if type(data.weather) == 'string' and data.weather ~= '' and VALID_WEATHER[data.weather] then
        lobbyMetadata.weather = data.weather
    end

    if type(data.time) == 'number' and data.time >= 0 and data.time <= 23 then
        lobbyMetadata.time = math.floor(data.time)
    end

    local success, err = lib.callback.await('uis:server:updateLobbyConfig', false, {
        password = data.password,
        slots = data.slots,
        mapId = data.mapId,
        gamemode = data.gamemode,
        metadata = lobbyMetadata,
        ffaLocationIndex = data.ffaLocationIndex
    })

    if not success then
        lib.print.error('updateLobbyConfig failed:', err)
        return cb({ success = false, error = err })
    end

    cb({ success = true })
end)

---@param data { teamA: integer[], teamB: integer[] }
RegisterNUICallback('startLobbyGame', function(data, cb)
    local success, err = lib.callback.await('uis:server:startLobbyGame', false, data)
    if not success and err then
        lib.print.error('startLobbyGame failed:', err)
        return cb({ success = false, error = err })
    end
    cb({ success = success or false })
end)

---@param ownerSource Source
RegisterNetEvent('uis:lobbyDisbanded', function(ownerSource)
    TriggerEvent('core:client:teleportToSpawn')
    clearMetadata()
    applyHeadshotState()
    clearLobbyEnvironment()
    clearLobbyWindyEffects()
    clearLobbyAimCooldown()

    SendNUIMessage({ action = 'setMyLobbyId', data = nil })

    if ownerSource ~= cache.serverId then
        ui:notify({ type = 'error', text = 'The owner disbanded the lobby' })
        SendNUIMessage({ action = 'lobbyDisbanded' })
    end
end)

RegisterNetEvent('uis:applyLobbyKillSiphon', function(maxArmor)
    if not next(metadata) or not metadata.siphon then
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

AddStateBagChangeHandler('isDead', ('player:%s'):format(cache.serverId), function(_, _, value)
    if not value then
        return
    end

    if not next(metadata) or not metadata.instantRevive then
        return
    end

    SetTimeout(1000, function()
        if not playerState.isDead then
            return
        end

        if not next(metadata) or not metadata.instantRevive then
            return
        end

        exports.core:reviveSelf(nil, true)
    end)
end)

CreateThread(function()
    while not playerState.uisReady do
        Wait(100)
    end

    local maps = {} ---@type LobbyMapEntry[]

    for k, v in pairs(locations) do
        if not v.disableLobbyUsage then
            maps[#maps + 1] = {
                desc = v.description,
                label = v.label,
                image = v.image,
                id = k
            }
        end
    end

    local payload = lib.callback.await('uis:server:getRankedLobbyMaps', false) ---@type string
    local decompressed = LibDeflate:DecompressDeflate(payload)

    if decompressed then
        local rankedMaps = json.decode(decompressed) ---@type LobbyMapEntry[]

        for _, map in pairs(rankedMaps) do
            maps[#maps + 1] = map
        end
    end

    SendNUIMessage({
        action = 'setLobbyMaps',
        data = maps
    })
end)