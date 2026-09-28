---Matchmaking: the queue, the accept prompt, and the map ban.
---
---Parties queue, not players -- a party of three enters as one unit and is
---never split across teams. The matcher pairs whole parties into two sides
---of equal size, widening the rating window it will accept the longer a
---party has waited, so a full lobby beats a perfect one.

Ranked = Ranked or {}

---Every mode the lobby offers. `label` is what the mode picker renders.
---@type { id: RankedModeType, label: string, teamSize: integer }[]
---Every one of these is ranked hopouts (Ranked.handOffToGamemode hands each
---match to hopouts); the id is the team size. `title` is what the mode card
---shows, so it says so -- the bare SOLO/DUO/... read as if hopouts was not
---on offer at all.
local GAME_MODES = {
    { id = 'solo', label = 'SOLO', title = 'HOPOUTS 1V1', teamSize = 1 },
    { id = 'duo', label = 'DUO', title = 'HOPOUTS 2V2', teamSize = 2 },
    { id = 'trio', label = 'TRIO', title = 'HOPOUTS 3V3', teamSize = 3 },
    { id = 'squad', label = 'SQUAD', title = 'HOPOUTS 4V4', teamSize = 4 },
}

---How far apart two parties' ratings may be, and how fast that widens.
local BASE_ELO_WINDOW = 150
local ELO_WINDOW_PER_SECOND = 10
local MAX_ELO_WINDOW = 2000

local MATCHMAKER_TICK_MS = 2000

---@type table<integer, integer> party id -> os.time queued
local queued = {}

---@type table<integer, RankedPendingMatch>
local pending = {}

---@class RankedPendingMatch
---@field id integer
---@field mode RankedModeType
---@field teams integer[][] two lists of userIds
---@field accepted table<integer, boolean>
---@field phase 'accept' | 'banning'
---@field deadline integer GetGameTimer value
---@field maps string[] map ids still in the pool
---@field bans table<integer, string> userId -> banned map id

local nextMatchId = 0

---The NUI's mode card reads every field below unguarded (`formations.map`,
---`elo.toLocaleString()`), so each one has to be present: a missing field
---throws inside React and blanks the whole UI, not just the card.
---@param userId integer
function Ranked.pushGameModes(userId)
    local modes = {}

    for index = 1, #GAME_MODES do
        local mode = GAME_MODES[index]
        local elo = Ranked.getElo(userId, mode.id)

        modes[index] = {
            id = mode.id,
            label = mode.label,
            title = mode.title,
            -- Shown above the title in the mode picker, where the NUI had a
            -- hardcoded "TITLE" placeholder.
            rankLabel = Ranked.getRankName(userId, mode.id):upper(),
            teamSize = mode.teamSize,
            maxSquadPlayers = mode.teamSize,
            -- Each mode is already a fixed squad size, so its one formation is
            -- itself. buildPartyData falls back to party.mode for the same
            -- reason, which keeps this button shown as selected.
            formations = { mode.id },
            elo = elo,
            -- The bar fills from minElo to maxElo: progress through the tier.
            minElo = Ranked.getTierFloorElo(elo),
            maxElo = Ranked.getNextTierElo(elo),
            hideElo = false,
        }
    end

    Ranked.push(userId, 'setRankedGameModes', modes)
end

---@param party RankedParty
---@return integer
local function partyElo(party)
    local total = 0

    for index = 1, #party.members do
        total += Ranked.getElo(party.members[index], party.mode)
    end

    return math.floor(total / math.max(1, #party.members))
end

---@param party RankedParty
---@return integer
local function waitedSeconds(party)
    local since = queued[party.id]

    return since and (os.time() - since) or 0
end

---@param a RankedParty
---@param b RankedParty
---@return boolean
local function withinEloWindow(a, b)
    local window = BASE_ELO_WINDOW
        + (math.max(waitedSeconds(a), waitedSeconds(b)) * ELO_WINDOW_PER_SECOND)

    return math.abs(partyElo(a) - partyElo(b)) <= math.min(MAX_ELO_WINDOW, window)
end

---@param party RankedParty
---@param reason string?
function Ranked.dequeueParty(party, reason)
    if not queued[party.id] then
        return
    end

    queued[party.id] = nil
    party.queuedAt = nil

    for index = 1, #party.members do
        Ranked.push(party.members[index], 'setDeathmatchQueueHud', false)
    end

    if reason then
        Ranked.log(('party %s left the queue (%s)'):format(party.id, reason))
    end
end

---@return boolean success
---@return string? error
lib.callback.register('ranked:server:togglePartyQueue', function(source)
    local userId = Ranked.getUserId(source)

    if not userId then
        return false, 'No player loaded.'
    end

    local party = Ranked.getParty(userId)

    if party.leaderId ~= userId then
        return false, 'Only the party leader can queue.'
    end

    if queued[party.id] then
        Ranked.dequeueParty(party, 'cancelled')
        Ranked.pushParty(party)

        return true
    end

    -- A timeout is served by the whole party, not just the offender: letting
    -- the rest queue without them would just be a shorter ban.
    for index = 1, #party.members do
        local secondsLeft = Ranked.getTimeoutSecondsLeft(party.members[index])

        if secondsLeft > 0 then
            Ranked.emit(party.members[index], 'ranked:displayTimeoutWarning', secondsLeft)

            if party.members[index] == userId then
                return false
            end

            return false, 'A party member has an active timeout.'
        end
    end

    if #party.members > Ranked.getModeSize(party.mode) then
        return false, 'Your party is too big for that mode.'
    end

    queued[party.id] = os.time()
    party.queuedAt = queued[party.id]

    for index = 1, #party.members do
        Ranked.push(party.members[index], 'setDeathmatchQueueHud', true)
    end

    Ranked.pushParty(party)

    return true
end)

-- ---------------------------------------------------------- the matcher ----

---Parties in the queue for one mode, longest wait first, so nobody is
---overtaken by a party that queued after them.
---@param mode RankedModeType
---@return RankedParty[]
local function queuedParties(mode)
    local list = {}

    for partyId in pairs(queued) do
        local party = Ranked.getAllParties()[partyId]

        if party and party.mode == mode then
            list[#list + 1] = party
        end
    end

    table.sort(list, function(a, b)
        return (queued[a.id] or 0) < (queued[b.id] or 0)
    end)

    return list
end

---Fills one side up to `teamSize` from the pool, taking whole parties only.
---@param pool RankedParty[]
---@param teamSize integer
---@param anchor RankedParty
---@return RankedParty[]?
local function buildTeam(pool, teamSize, anchor)
    local team = { anchor }
    local size = #anchor.members

    if size == teamSize then
        return team
    end

    for index = 1, #pool do
        local party = pool[index]

        if not party.taken and party ~= anchor and withinEloWindow(anchor, party) then
            if size + #party.members <= teamSize then
                team[#team + 1] = party
                size += #party.members

                if size == teamSize then
                    return team
                end
            end
        end
    end

    return nil
end

---@param teams RankedParty[][]
---@return integer[][]
local function toUserIds(teams)
    local out = {}

    for teamIndex = 1, #teams do
        local ids = {}

        for _, party in ipairs(teams[teamIndex]) do
            for index = 1, #party.members do
                ids[#ids + 1] = party.members[index]
            end
        end

        out[teamIndex] = ids
    end

    return out
end

---@param mode RankedModeType
---@param teamSize integer
---@param teams RankedParty[][]
local function startMatch(mode, teamSize, teams)
    nextMatchId += 1

    for _, team in ipairs(teams) do
        for _, party in ipairs(team) do
            Ranked.dequeueParty(party, 'matched')
        end
    end

    local userIds = toUserIds(teams)

    ---@type RankedPendingMatch
    local match = {
        id = nextMatchId,
        mode = mode,
        teams = userIds,
        accepted = {},
        phase = 'accept',
        deadline = GetGameTimer() + Ranked.config.matchAcceptTimeMsec,
        maps = Ranked.getMapPool(),
        allMaps = Ranked.getMapPool(),
        bans = {},
    }

    pending[match.id] = match

    local players = {}

    for teamIndex = 1, #userIds do
        for _, memberId in ipairs(userIds[teamIndex]) do
            local identity = Ranked.getIdentity(memberId)

            if identity then
                players[#players + 1] = {
                    userId = identity.userId,
                    username = identity.username,
                    avatar = identity.avatar,
                    team = teamIndex,
                    accepted = false,
                }
            end
        end
    end

    for teamIndex = 1, #userIds do
        for _, memberId in ipairs(userIds[teamIndex]) do
            Ranked.matchByUser[memberId] = match.id
            -- The popup reads totalPlayers / acceptedPlayers /
            -- startingSecondsCountdown. None of them were sent, so it kept its
            -- built-in placeholder (10 slots, 4 already accepted, 15s) and
            -- looked like a match other people had already started.
            Ranked.push(memberId, 'setMatchAcceptData', {
                matchId = match.id,
                mode = mode,
                teamSize = teamSize,
                totalPlayers = #players,
                acceptedPlayers = 0,
                startingSecondsCountdown = math.floor(Ranked.config.matchAcceptTimeMsec / 1000),
                players = players,
            })
            Ranked.push(memberId, 'setMatchAcceptVisible', true)
        end
    end

    Ranked.log(('match %s formed in %s'):format(match.id, mode))
end

---A full stack that is already the size of a team skips the wait entirely
---when another one is close enough on rating -- the config calls this the
---instant match, and it is what stops five-stacks sitting in the queue.
---@param mode RankedModeType
---@param teamSize integer
---@param pool RankedParty[]
---@return boolean matched
local function tryInstantMatch(mode, teamSize, pool)
    if teamSize < Ranked.config.fullStackInstantMatchMinSize then
        return false
    end

    for i = 1, #pool do
        for j = i + 1, #pool do
            local a, b = pool[i], pool[j]

            if not a.taken and not b.taken
                and #a.members == teamSize and #b.members == teamSize
                and math.abs(partyElo(a) - partyElo(b)) <= Ranked.config.fullStackInstantMatchMaxEloDifference then
                a.taken = true
                b.taken = true

                startMatch(mode, teamSize, { { a }, { b } })

                return true
            end
        end
    end

    return false
end

---@param mode RankedModeType
---@param teamSize integer
local function matchMode(mode, teamSize)
    local pool = queuedParties(mode)

    for index = 1, #pool do
        pool[index].taken = nil
    end

    if tryInstantMatch(mode, teamSize, pool) then
        return
    end

    for index = 1, #pool do
        local anchor = pool[index]

        if not anchor.taken then
            local teamA = buildTeam(pool, teamSize, anchor)

            if teamA then
                for _, party in ipairs(teamA) do
                    party.taken = true
                end

                local opponent

                for otherIndex = 1, #pool do
                    local candidate = pool[otherIndex]

                    if not candidate.taken and withinEloWindow(anchor, candidate) then
                        local teamB = buildTeam(pool, teamSize, candidate)

                        if teamB then
                            for _, party in ipairs(teamB) do
                                party.taken = true
                            end

                            opponent = teamB
                            break
                        end
                    end
                end

                if opponent then
                    startMatch(mode, teamSize, { teamA, opponent })
                else
                    -- Put the first team back; a half-formed match is worse
                    -- than leaving everyone queued another tick.
                    for _, party in ipairs(teamA) do
                        party.taken = nil
                    end
                end
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(MATCHMAKER_TICK_MS)

        for index = 1, #GAME_MODES do
            matchMode(GAME_MODES[index].id, GAME_MODES[index].teamSize)
        end

        Ranked.tickPendingMatches()
    end
end)

-- -------------------------------------------------------- accept & bans ----

---@param userId integer
---@return RankedPendingMatch?
local function pendingFor(userId)
    local matchId = Ranked.matchByUser[userId]

    return matchId and pending[matchId] or nil
end

---Everyone goes back where they came from. Used when a match is abandoned at
---the accept stage -- nobody has played anything, so nobody is penalised
---except whoever failed to accept.
---@param match RankedPendingMatch
---@param blameUserId integer?
local function cancelPending(match, blameUserId)
    pending[match.id] = nil

    for teamIndex = 1, #match.teams do
        for _, memberId in ipairs(match.teams[teamIndex]) do
            Ranked.matchByUser[memberId] = nil
            Ranked.push(memberId, 'setMatchAcceptVisible', false)
            Ranked.push(memberId, 'setMapBanVisible', false)
        end
    end

    if blameUserId then
        Ranked.applyTimeout(blameUserId, 'failed to accept a match')
    end
end

RegisterNetEvent('ranked:server:acceptMatch', function()
    local source = source --[[@as Source]]
    local userId = Ranked.getUserId(source)

    if not userId then
        return
    end

    local match = pendingFor(userId)

    if not match or match.phase ~= 'accept' then
        return
    end

    match.accepted[userId] = true

    local total, accepted = 0, 0

    for teamIndex = 1, #match.teams do
        for _, memberId in ipairs(match.teams[teamIndex]) do
            total += 1

            if match.accepted[memberId] then
                accepted += 1
            end
        end
    end

    for teamIndex = 1, #match.teams do
        for _, memberId in ipairs(match.teams[teamIndex]) do
            -- setMatchAcceptData, not setMatchFoundData: that one is the
            -- team-vs-team screen and expects teamBlue/teamRed lists.
            Ranked.push(memberId, 'setMatchAcceptData', { acceptedPlayers = accepted, totalPlayers = total })
        end
    end

    if accepted == total then
        Ranked.beginMapBan(match)
    end
end)

---@param match RankedPendingMatch
function Ranked.beginMapBan(match)
    match.phase = 'banning'
    match.deadline = GetGameTimer() + Ranked.config.matchBanningTimeMsec

    for teamIndex = 1, #match.teams do
        for _, memberId in ipairs(match.teams[teamIndex]) do
            Ranked.push(memberId, 'setMatchAcceptVisible', false)
            Ranked.push(memberId, 'setMapBanData', {
                maps = Ranked.buildMapEntries(match.allMaps, match.maps),
                startingSecondsCountdown = math.floor(Ranked.config.matchBanningTimeMsec / 1000),
                context = 'queue',
            })
            Ranked.push(memberId, 'setMapBanVisible', true)
        end
    end
end

---@param mapId string
---@return boolean
lib.callback.register('ranked:server:voteForMapBan', function(source, mapId)
    local userId = Ranked.getUserId(source)
    local match = userId and pendingFor(userId) or nil

    if not match or match.phase ~= 'banning' or type(mapId) ~= 'string' then
        return false
    end

    -- One ban each, and never the last map standing.
    if match.bans[userId] or #match.maps <= 1 then
        return false
    end

    for index = 1, #match.maps do
        if match.maps[index] == mapId then
            table.remove(match.maps, index)
            match.bans[userId] = mapId

            for teamIndex = 1, #match.teams do
                for _, memberId in ipairs(match.teams[teamIndex]) do
                    Ranked.push(memberId, 'setMapBanData', {
                        maps = Ranked.buildMapEntries(match.allMaps, match.maps),
                        bannedBy = { userId = userId, mapId = mapId },
                    })
                end
            end

            return true
        end
    end

    return false
end)

---@return boolean
lib.callback.register('ranked:server:voteForMapSkip', function(source)
    local userId = Ranked.getUserId(source)
    local match = userId and pendingFor(userId) or nil

    if not match or match.phase ~= 'banning' then
        return false
    end

    match.bans[userId] = 'skip'

    return true
end)

---Drives the accept and ban deadlines. Run from the matchmaker tick rather
---than a timer per match, so a match that ends early leaves nothing behind.
function Ranked.tickPendingMatches()
    local now = GetGameTimer()

    for _, match in pairs(pending) do
        if now >= match.deadline then
            if match.phase == 'accept' then
                local blame

                for teamIndex = 1, #match.teams do
                    for _, memberId in ipairs(match.teams[teamIndex]) do
                        if not match.accepted[memberId] then
                            blame = blame or memberId
                        end
                    end
                end

                cancelPending(match, blame)
            else
                Ranked.launchMatch(match)
            end
        end
    end
end

---@param match RankedPendingMatch
function Ranked.launchMatch(match)
    pending[match.id] = nil

    local mapId = match.maps[1]

    for teamIndex = 1, #match.teams do
        for _, memberId in ipairs(match.teams[teamIndex]) do
            Ranked.push(memberId, 'setMapBanVisible', false)
        end
    end

    if not mapId then
        return cancelPending(match, nil)
    end

    Ranked.handOffToGamemode(match, mapId)
end

---@param userId integer
function Ranked.onPlayerDroppedFromQueue(userId)
    local match = pendingFor(userId)

    if match and match.phase == 'accept' then
        cancelPending(match, userId)
    end
end

---@return table<integer, RankedPendingMatch>
function Ranked.getPendingMatches()
    return pending
end
