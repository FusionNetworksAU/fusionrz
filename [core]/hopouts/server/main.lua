Hopouts = Hopouts or {}

local core = exports.core

Hopouts.sharedConfig = require 'config.shared'
Hopouts.maps = require 'data.maps'

---@alias HopOutStateName
---| 'lobby'
---| 'warmup'
---| 'preround'
---| 'live'
---| 'roundend'
---| 'switchsides'
---| 'matchend'

---@type table<HopOutStateName, { enter: fun(match: HopOutMatch), tick: fun(match: HopOutMatch)?, exit: fun(match: HopOutMatch)? }>
Hopouts.states = Hopouts.states or {}

---@class HopOutPlayer
---@field source Source
---@field userId integer
---@field username string
---@field side string
---@field slot integer
---@field alive boolean
---@field kills integer
---@field deaths integer
---@field assists integer
---@field damage integer
---@field roundKills integer
---@field connected boolean

---@class HopOutMatch
---@field id integer
---@field bucket integer
---@field map HopOutMap
---@field state HopOutStateName
---@field stateEnteredAt integer
---@field stateDeadline integer? os.clock ms after which the state advances
---@field round integer
---@field scores table<string, integer>
---@field sides string[]
---@field players table<Source, HopOutPlayer>
---@field roundsToWin integer
---@field roundsPerHalf integer
---@field swapped boolean
---@field data table scratch space, WIPED on every state change
---@field vehicles integer[]? entities spawned for the current round
---@field loadout table? the kit the current round handed out
---@field roundWinner string? side that took the round being scored

---@type table<integer, HopOutMatch>
local matches = {}

---@type table<Source, integer>
local matchBySource = {}

local nextMatchId = 1

Hopouts.matches = matches

---@param source Source
---@return HopOutMatch?
function Hopouts.getMatchForPlayer(source)
    local matchId = matchBySource[source]

    return matchId and matches[matchId] or nil
end

---@param matchId integer
---@return HopOutMatch?
function Hopouts.getMatch(matchId)
    return matches[matchId]
end

---@param match HopOutMatch
---@param source Source
---@return HopOutPlayer?
function Hopouts.getPlayer(match, source)
    return match.players[source]
end

---@param match HopOutMatch
---@param side string?
---@return HopOutPlayer[]
function Hopouts.getPlayers(match, side)
    local list = {}

    for _, player in pairs(match.players) do
        if not side or player.side == side then
            list[#list + 1] = player
        end
    end

    return list
end

---@param match HopOutMatch
---@param eventName string
---@param ... any
function Hopouts.broadcast(match, eventName, ...)
    for playerSource in pairs(match.players) do
        TriggerClientEvent(eventName, playerSource, ...)
    end
end

---@param match HopOutMatch
---@param stateName HopOutStateName
---@param durationMsec integer? nil means the state ends itself
function Hopouts.setState(match, stateName, durationMsec)
    local previous = Hopouts.states[match.state]

    if previous and previous.exit then
        previous.exit(match)
    end

    match.state = stateName
    match.stateEnteredAt = GetGameTimer()
    match.stateDeadline = durationMsec and (match.stateEnteredAt + durationMsec) or nil
    match.data = {}

    local handler = Hopouts.states[stateName]

    if not handler then
        return lib.print.error(('[hopouts] no handler for state "%s"'):format(stateName))
    end

    Hopouts.broadcast(match, 'hopouts:client:state', stateName, durationMsec)
    TriggerEvent('hopouts:server:onStateChanged', match.id, stateName)

    handler.enter(match)
end

---@param match HopOutMatch
---@return integer msec
function Hopouts.getStateRemaining(match)
    if not match.stateDeadline then
        return 0
    end

    return math.max(0, match.stateDeadline - GetGameTimer())
end

---@class HopOutMatchOptions
---@field mapId string
---@field players { source: Source, side: string? }[]
---@field roundsToWin integer?
---@field sides string[]?

---@param options HopOutMatchOptions
---@return integer? matchId
---@return string? error
function Hopouts.createMatch(options)
    if type(options) ~= 'table' then
        return nil, 'Invalid options.'
    end

    local map = Hopouts.maps[options.mapId]

    if not map or map.enabled == false then
        return nil, 'Unknown map.'
    end

    local sides = options.sides or { 'A', 'B' }

    for index = 1, #sides do
        if not map.sides[sides[index]] then
            return nil, ('Map %s has no spawns for side %s.'):format(map.id, sides[index])
        end
    end

    local lease = core:CreateBucket('hopouts', ('hopouts:%s'):format(map.id))
    -- Every hopouts match is first to 5 (halftime swap after round 4).
    local roundsToWin = options.roundsToWin or 5

    ---@type HopOutMatch
    local match = {
        id = nextMatchId,
        bucket = lease.id,
        map = map,
        state = 'lobby',
        stateEnteredAt = GetGameTimer(),
        stateDeadline = nil,
        round = 0,
        scores = {},
        sides = sides,
        players = {},
        roundsToWin = options.roundsToWin or 5,
        roundsPerHalf = (options.roundsToWin or 5) - 1,
        swapped = false,
        data = {},
        vehicles = nil,
        loadout = nil,
    }

    for index = 1, #sides do
        match.scores[sides[index]] = 0
    end

    matches[nextMatchId] = match
    nextMatchId += 1

    for index = 1, #(options.players or {}) do
        local entry = options.players[index]

        Hopouts.addPlayer(match, entry.source, entry.side)
    end

    Hopouts.setState(match, 'warmup', 10000)

    return match.id
end

---@param match HopOutMatch
---@param source Source
---@param side string?
---@return boolean success
---@return string? error
function Hopouts.addPlayer(match, source, side)
    if match.players[source] then
        return false, 'Already in this match.'
    end

    local existing = Hopouts.getMatchForPlayer(source)

    if existing then
        return false, 'Already in a match.'
    end

    local data = core:GetPlayerData(source)

    if not data then
        return false, 'No player loaded.'
    end

    side = side or Hopouts.pickSide(match)

    local slot = #Hopouts.getPlayers(match, side) + 1
    local spawns = match.map.sides[side]

    if not spawns or slot > #spawns then
        return false, 'That side is full.'
    end

    match.players[source] = {
        source = source,
        userId = data.userId,
        username = data.username,
        side = side,
        slot = slot,
        alive = false,
        kills = 0,
        deaths = 0,
        assists = 0,
        damage = 0,
        roundKills = 0,
        connected = true,
    }

    matchBySource[source] = match.id

    core:SetPlayerBucket(source, match.bucket)

    TriggerClientEvent('hopouts:client:joined', source, {
        matchId = match.id,
        mapId = match.map.id,
        side = side,
        slot = slot,
        colours = Hopouts.getSideColours(match),
    })

    Hopouts.broadcastRoster(match)

    return true
end

---@param match HopOutMatch
---@param source Source
---@param reason string?
function Hopouts.removePlayer(match, source, reason)
    local player = match.players[source]

    if not player then
        return
    end

    match.players[source] = nil
    matchBySource[source] = nil

    if GetPlayerName(source --[[@as string]]) then
        TriggerClientEvent('hopouts:client:left', source, reason)

        core:SetPlayerBucket(source, 0)
        core:TeleportToSpawn(source)
    end

    Hopouts.broadcastRoster(match)

    for index = 1, #match.sides do
        if #Hopouts.getPlayers(match, match.sides[index]) == 0 and match.state ~= 'matchend' then
            Hopouts.setState(match, 'matchend', Hopouts.sharedConfig.winnerPreviewDurationMsec)

            return
        end
    end
end

---@param matchId integer
---@param reason string?
function Hopouts.destroyMatch(matchId, reason)
    local match = matches[matchId]

    if not match then
        return
    end

    for playerSource in pairs(match.players) do
        Hopouts.removePlayer(match, playerSource, reason)
    end

    Hopouts.despawnVehicles(match)

    core:DestroyBucket(match.bucket)

    matches[matchId] = nil

    TriggerEvent('hopouts:server:onMatchEnded', matchId)
end

CreateThread(function()
    while true do
        for _, match in pairs(matches) do
            local handler = Hopouts.states[match.state]

            if handler then
                if match.stateDeadline and GetGameTimer() >= match.stateDeadline then
                    match.stateDeadline = nil

                    if handler.timeout then
                        handler.timeout(match)
                    end
                elseif handler.tick then
                    handler.tick(match)
                end
            end
        end

        Wait(250)
    end
end)

AddEventHandler('core:server:onPlayerDropped', function(source)
    local match = Hopouts.getMatchForPlayer(source)

    if match then
        Hopouts.removePlayer(match, source, 'disconnected')
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    for matchId in pairs(matches) do
        Hopouts.destroyMatch(matchId, 'resource stopped')
    end
end)

exports('CreateMatch', Hopouts.createMatch)
exports('DestroyMatch', Hopouts.destroyMatch)

---@param source Source
---@return integer?
exports('GetMatchId', function(source)
    local match = Hopouts.getMatchForPlayer(source)

    return match and match.id or nil
end)

---@param matchId integer
---@return table?
exports('GetMatchSummary', function(matchId)
    local match = matches[matchId]

    if not match then
        return nil
    end

    return {
        id = match.id,
        mapId = match.map.id,
        state = match.state,
        round = match.round,
        scores = match.scores,
        players = Hopouts.buildScoreboard(match),
    }
end)
