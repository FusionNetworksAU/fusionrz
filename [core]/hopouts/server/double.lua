Hopouts = Hopouts or {}

---@class HopOutDoubleVote
---@field votes table<Source, boolean>
---@field bans table<string, integer> mapId -> ban count
---@field skips integer
---@field deadline integer

---@param match HopOutMatch
---@return HopOutDoubleVote
local function ensureVote(match)
    if not match.double then
        match.double = {
            votes = {},
            bans = {},
            skips = 0,
            deadline = GetGameTimer() + Hopouts.sharedConfig.requestDoubleDurationMsec,
        }
    end

    return match.double
end

---@param match HopOutMatch
---@param side string
---@return integer
local function countAccepted(match, side)
    local vote = match.double

    if not vote then
        return 0
    end

    local count = 0

    for playerSource, accepted in pairs(vote.votes) do
        local player = match.players[playerSource]

        if accepted and player and player.side == side then
            count += 1
        end
    end

    return count
end

---@param match HopOutMatch
---@return boolean
local function everyoneAccepted(match)
    local vote = match.double

    if not vote then
        return false
    end

    for playerSource, player in pairs(match.players) do
        if player.connected and vote.votes[playerSource] ~= true then
            return false
        end
    end

    return next(match.players) ~= nil
end

---@param match HopOutMatch
function Hopouts.startRequestDouble(match)
    local vote = ensureVote(match)

    local teams = {}

    for index = 1, #match.sides do
        local side = match.sides[index]

        teams[#teams + 1] = {
            id = side,
            name = side,
            numAccepted = 0,
            numPlayers = #Hopouts.getPlayers(match, side),
        }
    end

    Hopouts.broadcast(match, 'hopouts:client:requestDouble', {
        teams = teams,
        durationMsec = Hopouts.sharedConfig.requestDoubleDurationMsec,
        maps = Hopouts.getVotableMaps(),
    })

    vote.deadline = GetGameTimer() + Hopouts.sharedConfig.requestDoubleDurationMsec
end

---@param source Source
---@param accepted boolean
---@return boolean success
function Hopouts.submitDoubleVote(source, accepted)
    local match = Hopouts.getMatchForPlayer(source)

    if not match or not match.double then
        return false
    end

    if GetGameTimer() > match.double.deadline then
        return false
    end

    match.double.votes[source] = accepted == true

    for index = 1, #match.sides do
        local side = match.sides[index]

        Hopouts.broadcast(match, 'hopouts:client:requestDoubleCount', side, countAccepted(match, side))
    end

    if accepted == false then
        Hopouts.broadcast(match, 'hopouts:client:requestDoubleFailed')

        match.double = nil

        return true
    end

    if everyoneAccepted(match) then
        Hopouts.beginDoubleMapVote(match)
    end

    return true
end

---@return { id: string, label: string, image: string? }[]
function Hopouts.getVotableMaps()
    local list = {}

    for id, map in pairs(Hopouts.maps) do
        if map.enabled ~= false then
            list[#list + 1] = { id = id, label = map.label, image = map.image }
        end
    end

    table.sort(list, function(a, b) return a.id < b.id end)

    return list
end

---@param match HopOutMatch
function Hopouts.beginDoubleMapVote(match)
    match.double.bans = {}
    match.double.skips = 0

    Hopouts.broadcast(match, 'hopouts:client:doubleMapVote', {
        maps = Hopouts.getVotableMaps(),
        durationMsec = Hopouts.sharedConfig.requestDoubleDurationMsec,
    })
end

---@param match HopOutMatch
---@return string? mapId
local function resolveMap(match)
    local candidates = Hopouts.getVotableMaps()
    local bans = match.double and match.double.bans or {}

    ---@type string[]
    local remaining = {}

    for index = 1, #candidates do
        local id = candidates[index].id

        if (bans[id] or 0) == 0 then
            remaining[#remaining + 1] = id
        end
    end

    if #remaining == 0 then
        for index = 1, #candidates do
            remaining[index] = candidates[index].id
        end
    end

    if #remaining == 0 then
        return nil
    end

    return remaining[math.random(#remaining)]
end

---@param match HopOutMatch
function Hopouts.finishDoubleMapVote(match)
    local mapId = resolveMap(match)

    match.double = nil

    if not mapId then
        return Hopouts.broadcast(match, 'hopouts:client:requestDoubleFailed')
    end

    ---@type { source: Source, side: string }[]
    local players = {}

    for playerSource, player in pairs(match.players) do
        players[#players + 1] = { source = playerSource, side = player.side }
    end

    local oldId = match.id

    Hopouts.destroyMatch(oldId, 'rematch')

    local newId, err = Hopouts.createMatch({
        mapId = mapId,
        players = players,
        roundsToWin = match.roundsToWin,
        sides = match.sides,
    })

    if not newId then
        lib.print.error(('[hopouts] rematch failed: %s'):format(err))
    end
end

---@param mapId string
---@return boolean success
lib.callback.register('hopouts:server:voteForDoubleMapBan', function(source, mapId)
    local match = Hopouts.getMatchForPlayer(source)

    if not match or not match.double or type(mapId) ~= 'string' then
        return false
    end

    if not Hopouts.maps[mapId] then
        return false
    end

    local vote = match.double

    vote.bans[mapId] = (vote.bans[mapId] or 0) + 1

    Hopouts.broadcast(match, 'hopouts:client:doubleMapBanned', mapId, vote.bans[mapId])

    if vote.bans[mapId] + vote.skips >= #Hopouts.getPlayers(match) then
        Hopouts.finishDoubleMapVote(match)
    end

    return true
end)

---@return boolean success
lib.callback.register('hopouts:server:voteForDoubleMapSkip', function(source)
    local match = Hopouts.getMatchForPlayer(source)

    if not match or not match.double then
        return false
    end

    match.double.skips += 1

    local totalBans = 0

    for _, count in pairs(match.double.bans) do
        totalBans += count
    end

    if totalBans + match.double.skips >= #Hopouts.getPlayers(match) then
        Hopouts.finishDoubleMapVote(match)
    end

    return true
end)

---@param vote boolean
---@return boolean success
lib.callback.register('hopouts:server:submitDoubleVote', function(source, vote)
    return Hopouts.submitDoubleVote(source, vote == true)
end)
