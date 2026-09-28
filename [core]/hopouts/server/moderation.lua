Hopouts = Hopouts or {}

local core = exports.core

local KICK_THRESHOLD = 0.67

---@param match HopOutMatch
---@param targetUserId integer
---@return HopOutPlayer?
local function findByUserId(match, targetUserId)
    for _, player in pairs(match.players) do
        if player.userId == targetUserId then
            return player
        end
    end

    return nil
end

RegisterNetEvent('hopouts:server:voteToKick', function(targetUserId)
    local source = source --[[@as Source]]
    local match = Hopouts.getMatchForPlayer(source)

    if not match then
        return
    end

    local voter = match.players[source]
    local target = findByUserId(match, tonumber(targetUserId) or -1)

    if not voter or not target or target.source == source then
        return
    end

    if voter.side ~= target.side then
        return
    end

    match.kickVotes = match.kickVotes or {}
    match.kickVotes[target.userId] = match.kickVotes[target.userId] or {}
    match.kickVotes[target.userId][source] = true

    local teammates = Hopouts.getPlayers(match, target.side)
    local eligible = math.max(1, #teammates - 1)
    local votes = 0

    for voterSource in pairs(match.kickVotes[target.userId]) do
        if match.players[voterSource] then
            votes += 1
        end
    end

    Hopouts.broadcast(match, 'hopouts:client:kickVote', {
        userId = target.userId,
        votes = votes,
        required = math.ceil(eligible * KICK_THRESHOLD),
    })

    if votes < math.ceil(eligible * KICK_THRESHOLD) then
        return
    end

    core:Log('commands', ('[hopouts] %s (%s) vote-kicked from match %s'):format(
        target.username, target.userId, match.id
    ))

    match.kickVotes[target.userId] = nil

    Hopouts.removePlayer(match, target.source, 'vote kicked')
end)

---@param targetUserId integer
---@return boolean isMuted
lib.callback.register('hopouts:server:togglePlayerMute', function(source, targetUserId)
    local match = Hopouts.getMatchForPlayer(source)

    if not match then
        return false
    end

    match.mutes = match.mutes or {}
    match.mutes[source] = match.mutes[source] or {}

    local current = match.mutes[source][targetUserId]

    match.mutes[source][targetUserId] = not current or nil

    return match.mutes[source][targetUserId] == true
end)

AddEventHandler('core:server:onPlayerDropped', function(source)
    local match = Hopouts.getMatchForPlayer(source)

    if not match then
        return
    end

    if match.mutes then
        match.mutes[source] = nil
    end

    if match.kickVotes then
        for _, voters in pairs(match.kickVotes) do
            voters[source] = nil
        end
    end
end)
