---Live matches, rating, and the penalties around leaving one.
---
---Ranked does not run the match itself -- hopouts does. This file forms the
---teams, hands them over, and is what hopouts' result comes back to. Rating
---and timeouts are the two things that outlive the match, so they are the two
---things written to the database.

Ranked = Ranked or {}

local core = exports.core

---@type table<integer, integer> userId -> pending or live match id
Ranked.matchByUser = Ranked.matchByUser or {}

---@class RankedLiveMatch
---@field id integer
---@field mode RankedModeType
---@field mapId string
---@field teams integer[][]
---@field hopoutsId integer?
---@field startedAt integer
---@field continue table<integer, boolean>

---@type table<integer, RankedLiveMatch>
local live = {}

local STARTING_ELO = 1000

---How long the match result screen stays up before it closes itself.
local MATCH_ENDED_DISPLAY_MSEC = 8000
local K_FACTOR = 32

---Leaving a live match costs this much queue time.
local TIMEOUT_SECONDS = 15 * 60

-- ----------------------------------------------------------------- elo -----

---@param userId integer
---@param mode string
---@return integer
function Ranked.getElo(userId, mode)
    local elo = MySQL.scalar.await(
        'SELECT elo FROM ranked_elo WHERE user_id = ? AND mode = ?',
        { userId, mode }
    )

    return elo or STARTING_ELO
end

---Standard Elo, with the team's average standing in for a single opponent
---rating. Everyone on a side moves by the same amount, which is what keeps a
---party's members from drifting apart from each other.
---@param teamElo integer
---@param opponentElo integer
---@param won boolean
---@return integer delta
local function eloDelta(teamElo, opponentElo, won)
    local expected = 1 / (1 + 10 ^ ((opponentElo - teamElo) / 400))
    local actual = won and 1 or 0

    return math.floor(K_FACTOR * (actual - expected) + 0.5)
end

---@param userIds integer[]
---@param mode string
---@return integer
local function averageElo(userIds, mode)
    if #userIds == 0 then
        return STARTING_ELO
    end

    local total = 0

    for index = 1, #userIds do
        total += Ranked.getElo(userIds[index], mode)
    end

    return math.floor(total / #userIds)
end

---@param userId integer
---@param mode string
---@param delta integer
---@param won boolean
local function applyElo(userId, mode, delta, won)
    local before = Ranked.getElo(userId, mode)
    local after = math.max(0, before + delta)

    MySQL.query.await([[
        INSERT INTO ranked_elo (user_id, mode, elo, wins, losses, games)
        VALUES (?, ?, ?, ?, ?, 1)
        ON DUPLICATE KEY UPDATE
            elo = VALUES(elo),
            wins = wins + VALUES(wins),
            losses = losses + VALUES(losses),
            games = games + 1
    ]], { userId, mode, after, won and 1 or 0, won and 0 or 1 })

    -- Written down rather than only sent: a player who disconnects on the
    -- result screen still sees the change next time they open the lobby.
    MySQL.insert.await([[
        INSERT INTO ranked_elo_adjustments (user_id, mode, delta, elo_before, elo_after, won)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { userId, mode, delta, before, after, won and 1 or 0 })

    Ranked.pushPendingEloAdjustments(userId)
end

---@param userId integer
function Ranked.pushPendingEloAdjustments(userId)
    local rows = MySQL.query.await([[
        SELECT id, mode, delta, elo_before AS eloBefore, elo_after AS eloAfter, won
        FROM ranked_elo_adjustments
        WHERE user_id = ? AND acknowledged = 0
        ORDER BY created_at ASC
    ]], { userId }) or {}

    if #rows == 0 then
        return
    end

    local latest = rows[#rows]

    Ranked.emit(userId, 'ranked:displayEloAdjustment', {
        mode = latest.mode,
        delta = latest.delta,
        eloBefore = latest.eloBefore,
        eloAfter = latest.eloAfter,
        won = latest.won == 1,
        pending = #rows,
    })
end

RegisterNetEvent('ranked:server:fetchEloAdjustments', function()
    local source = source --[[@as Source]]
    local userId = Ranked.getUserId(source)

    if userId then
        Ranked.pushPendingEloAdjustments(userId)
    end
end)

---@return boolean success
---@return string? error
lib.callback.register('ranked:server:acknowledgeEloAdjustments', function(source)
    local userId = Ranked.getUserId(source)

    if not userId then
        return false, 'No player loaded.'
    end

    MySQL.query.await(
        'UPDATE ranked_elo_adjustments SET acknowledged = 1 WHERE user_id = ? AND acknowledged = 0',
        { userId }
    )

    return true
end)

-- ------------------------------------------------------------ timeouts -----

---@param userId integer
---@return integer seconds, 0 when not timed out
function Ranked.getTimeoutSecondsLeft(userId)
    local expires = MySQL.scalar.await(
        'SELECT UNIX_TIMESTAMP(expires_at) FROM ranked_timeouts WHERE user_id = ?',
        { userId }
    )

    if not expires then
        return 0
    end

    local left = expires - os.time()

    if left <= 0 then
        MySQL.query.await('DELETE FROM ranked_timeouts WHERE user_id = ?', { userId })

        return 0
    end

    return left
end

---@param userId integer
---@param reason string
function Ranked.applyTimeout(userId, reason)
    MySQL.query.await([[
        INSERT INTO ranked_timeouts (user_id, expires_at, reason)
        VALUES (?, DATE_ADD(NOW(), INTERVAL ? SECOND), ?)
        ON DUPLICATE KEY UPDATE expires_at = VALUES(expires_at), reason = VALUES(reason)
    ]], { userId, TIMEOUT_SECONDS, reason })

    Ranked.emit(userId, 'ranked:displayTimeoutWarning', TIMEOUT_SECONDS)
    Ranked.log(('%s timed out for %s'):format(userId, reason))
end

-- ----------------------------------------------------------- map pool ------

---The maps ranked draws from: hopouts' enabled maps, since hopouts is what
---actually runs the match.
---@return string[]
function Ranked.getMapPool()
    local pool = {}

    if GetResourceState('hopouts') ~= 'started' then
        return pool
    end

    local maps = require '@hopouts.data.maps'

    for id, map in pairs(maps) do
        if map.enabled then
            pool[#pool + 1] = map.id or id
        end
    end

    table.sort(pool)

    return pool
end

---The map-ban cards. The screen reads `imagePath` (it was sent `image`, so
---every card was blank) and `isBanned`, and keeps banned maps on screen
---greyed out rather than having them vanish.
---@param mapIds string[] every map in the vote, banned or not
---@param remaining string[]? the maps still in the pool; nil = none banned
---@return table[]
function Ranked.buildMapEntries(mapIds, remaining)
    local maps = GetResourceState('hopouts') == 'started' and require '@hopouts.data.maps' or {}
    local stillIn

    if remaining then
        stillIn = {}

        for index = 1, #remaining do
            stillIn[remaining[index]] = true
        end
    end

    local entries = {}

    for index = 1, #mapIds do
        local id = mapIds[index]
        local map = maps[id]

        entries[index] = {
            id = id,
            label = map and map.label or id,
            image = map and map.image or nil,
            imagePath = map and map.image or nil,
            isBanned = stillIn ~= nil and not stillIn[id],
        }
    end

    return entries
end

---@param match RankedPendingMatch
---@param reason string
local function abandonHandOff(match, reason)
    Ranked.log(('match %s could not start: %s'):format(match.id, reason))

    for teamIndex = 1, #match.teams do
        for _, memberId in ipairs(match.teams[teamIndex]) do
            Ranked.matchByUser[memberId] = nil

            Ranked.push(memberId, 'setMapBanVisible', false)
            Ranked.push(memberId, 'setMatchAcceptVisible', false)
            Ranked.push(memberId, 'notify', {
                type = 'error',
                text = ('The match could not start (%s). You can queue again.'):format(reason),
                duration = 6000,
            })
        end
    end
end

---@param match RankedPendingMatch
---@param mapId string
function Ranked.handOffToGamemode(match, mapId)
    if GetResourceState('hopouts') ~= 'started' then
        return abandonHandOff(match, 'hopouts is not running')
    end

    local sides = { 'A', 'B' }
    local players = {}

    for teamIndex = 1, #match.teams do
        for _, memberId in ipairs(match.teams[teamIndex]) do
            local playerSource = Ranked.getSource(memberId)

            if playerSource then
                players[#players + 1] = { source = playerSource, side = sides[teamIndex] }
            end
        end
    end

    local hopoutsId, err = exports.hopouts:CreateMatch({
        mapId = mapId,
        players = players,
        sides = sides,
    })

    if not hopoutsId then
        return abandonHandOff(match, err or 'hopouts refused it')
    end

    live[match.id] = {
        id = match.id,
        mode = match.mode,
        mapId = mapId,
        teams = match.teams,
        hopoutsId = hopoutsId,
        startedAt = os.time(),
        continue = {},
    }

    Ranked.log(('match %s started on %s as hopouts %s'):format(match.id, mapId, hopoutsId))
end

---@param hopoutsId integer
---@return RankedLiveMatch?
local function findByHopoutsId(hopoutsId)
    for _, match in pairs(live) do
        if match.hopoutsId == hopoutsId then
            return match
        end
    end

    return nil
end

---@param match RankedLiveMatch
---@param result table? hopouts:server:matchApplied payload
---@return integer? winnerTeamIndex nil for a draw
local function winningTeam(match, result)
    local winningSide = result and result.winningSide

    if not winningSide then
        return nil
    end

    local sideOf = {}

    for _, row in ipairs(result.players or {}) do
        sideOf[row.userId] = row.side
    end

    for teamIndex = 1, #match.teams do
        for _, memberId in ipairs(match.teams[teamIndex]) do
            if sideOf[memberId] == winningSide then
                return teamIndex
            end
        end
    end

    return nil
end

---@param match RankedLiveMatch
---@param result table?
local function settleMatch(match, result)
    live[match.id] = nil

    local winner = winningTeam(match, result)

    local eloA = averageElo(match.teams[1], match.mode)
    local eloB = averageElo(match.teams[2], match.mode)

    local deltaA = winner and eloDelta(eloA, eloB, winner == 1) or 0
    local deltaB = winner and eloDelta(eloB, eloA, winner == 2) or 0

    local everyone = {}

    for teamIndex = 1, #match.teams do
        local delta = teamIndex == 1 and deltaA or deltaB
        local won = winner == teamIndex

        for _, memberId in ipairs(match.teams[teamIndex]) do
            local eloBefore = Ranked.getElo(memberId, match.mode)

            if winner then
                applyElo(memberId, match.mode, delta, won)
            end

            Ranked.matchByUser[memberId] = nil
            everyone[#everyone + 1] = memberId

            local before = Ranked.getRankProgress(eloBefore)
            local after = Ranked.getRankProgress(math.max(0, eloBefore + delta))

            Ranked.push(memberId, 'setMatchEndedData', {
                eloChange = delta,
                currentRank = before.rank,
                currentRankLabel = before.label,
                newRank = after.rank,
                newRankLabel = after.label,
                nextRank = before.nextRank,
                nextRankLabel = before.nextRankLabel,
                currentEloForNextRank = before.intoTier,
                totalEloRequiredForNextRank = before.tierSize,
                isTopRank = before.isTop,
            })
            Ranked.push(memberId, 'setMatchEndedVisible', true)

            Ranked.pushGameModes(memberId)
        end
    end

    local refreshed = {}

    for _, memberId in ipairs(everyone) do
        local party = Ranked.getPartyIfExists(memberId)

        if party and not refreshed[party] then
            refreshed[party] = true
            Ranked.pushParty(party)
        end
    end

    Ranked.recordRecentlyPlayed(everyone)

    SetTimeout(MATCH_ENDED_DISPLAY_MSEC, function()
        for _, memberId in ipairs(everyone) do
            Ranked.push(memberId, 'setMatchEndedVisible', false)
        end
    end)
end

AddEventHandler('hopouts:server:matchApplied', function(hopoutsId, result)
    local match = findByHopoutsId(hopoutsId)

    if match then
        settleMatch(match, result)
    end
end)

AddEventHandler('hopouts:server:onMatchEnded', function(hopoutsId)
    local match = findByHopoutsId(hopoutsId)

    if match then
        settleMatch(match, nil)
    end
end)

---@type table<integer, RankedLiveMatch>
local continuing = {}

---@param match RankedLiveMatch
function Ranked.offerContinueLobby(match)
    continuing[match.id] = match

    for teamIndex = 1, #match.teams do
        for _, memberId in ipairs(match.teams[teamIndex]) do
            Ranked.push(memberId, 'setContinueLobbyTitle', 'PLAY AGAIN?')
            Ranked.push(memberId, 'setContinueLobbyData', {
                mode = match.mode,
                seconds = math.floor(Ranked.config.queueOpenTimeMsec / 1000),
            })
            Ranked.push(memberId, 'setContinueLobbyVisible', true)
        end
    end

    SetTimeout(Ranked.config.queueOpenTimeMsec, function()
        local pendingMatch = continuing[match.id]

        if not pendingMatch then
            return
        end

        continuing[match.id] = nil

        for teamIndex = 1, #pendingMatch.teams do
            for _, memberId in ipairs(pendingMatch.teams[teamIndex]) do
                Ranked.push(memberId, 'setContinueLobbyVisible', false)
            end
        end
    end)
end

---@param continue boolean
RegisterNetEvent('ranked:server:setContinueLobbyResult', function(continue)
    local source = source --[[@as Source]]
    local userId = Ranked.getUserId(source)

    if not userId then
        return
    end

    for _, match in pairs(continuing) do
        for teamIndex = 1, #match.teams do
            for _, memberId in ipairs(match.teams[teamIndex]) do
                if memberId == userId then
                    match.continue[userId] = continue == true

                    Ranked.push(userId, 'setContinueLobbyVisible', false)

                    return
                end
            end
        end
    end
end)

---@param userId integer
function Ranked.offerReconnect(userId)
    local matchId = Ranked.matchByUser[userId]
    local match = matchId and live[matchId] or nil

    if not match then
        return
    end

    Ranked.emit(userId, 'ranked:notifyReconnect', match.mode)
end

---@param accepted boolean
RegisterNetEvent('ranked:server:reconnectToMatch', function(accepted)
    local source = source --[[@as Source]]
    local userId = Ranked.getUserId(source)

    if not userId then
        return
    end

    local matchId = Ranked.matchByUser[userId]
    local match = matchId and live[matchId] or nil

    if not match then
        return
    end

    if not accepted then
        Ranked.matchByUser[userId] = nil
        Ranked.applyTimeout(userId, 'abandoned a match')

        return
    end

    local side = nil

    for teamIndex = 1, #match.teams do
        for _, memberId in ipairs(match.teams[teamIndex]) do
            if memberId == userId then
                side = teamIndex == 1 and 'A' or 'B'
            end
        end
    end

    if side and GetResourceState('hopouts') == 'started' then
        exports.hopouts:CreateMatch({
            mapId = match.mapId,
            players = { { source = source, side = side } },
            sides = { 'A', 'B' },
        })
    end
end)

---@param userId integer
function Ranked.onPlayerDroppedFromMatch(userId)
    local matchId = Ranked.matchByUser[userId]

    if matchId and live[matchId] then
        Ranked.applyTimeout(userId, 'left a live match')
    end
end

---@param value boolean
---@return boolean success
---@return string? error
lib.callback.register('ranked:server:confirmClips', function(source, value)
    local userId = Ranked.getUserId(source)

    if not userId then
        return false, 'No player loaded.'
    end

    if value ~= true then
        return false, 'You must confirm clips are on to play ranked.'
    end

    core:SetMetadata(source, 'ranked_clips_confirmed', os.time())

    return true
end)

---@return boolean success
---@return string? error
lib.callback.register('ranked:server:startLobby', function(source)
    local userId = Ranked.getUserId(source)

    if not userId then
        return false, 'No player loaded.'
    end

    local secondsLeft = Ranked.getTimeoutSecondsLeft(userId)

    if secondsLeft > 0 then
        Ranked.emit(userId, 'ranked:displayTimeoutWarning', secondsLeft)

        return false
    end

    local party = Ranked.getParty(userId)

    if party.leaderId ~= userId then
        return false, 'Only the party leader can start.'
    end

    return true
end)

---@return integer[]
function Ranked.getLiveMatchIds()
    local ids = {}

    for matchId in pairs(live) do
        ids[#ids + 1] = matchId
    end

    return ids
end

exports('GetElo', function(userId, mode)
    return Ranked.getElo(userId, mode or 'solo')
end)

---@param userId integer
---@return string
exports('GetRankName', function(userId)
    local matchId = Ranked.matchByUser[userId]
    local match = matchId and live[matchId] or nil

    return Ranked.getRankName(userId, match and match.mode or 'solo')
end)

exports('GetTimeoutSecondsLeft', function(userId)
    return Ranked.getTimeoutSecondsLeft(userId)
end)

exports('IsInMatch', function(userId)
    local matchId = Ranked.matchByUser[userId]

    return matchId ~= nil and live[matchId] ~= nil
end)
