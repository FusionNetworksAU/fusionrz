---Developer commands.
---
---The lobby resource that would normally create a match does not exist, so
---until it does these are the only way to get one running. All restricted
---to group.admin, and all off unless `hopouts:debug 1` is set (or the
---server is not running as env=production).

Hopouts = Hopouts or {}

local core = exports.core

---Two ways in, because flipping the global `env` convar to get these
---commands would also change how core logs and would switch on /coretests.
---`hopouts:debug 1` turns on just this resource's dev commands.
---@return boolean
local function isDebugEnabled()
    if GetConvarInt('hopouts:debug', 0) == 1 then
        return true
    end

    return GetConvar('env', 'production') ~= 'production'
end

---@param source Source
---@param message string
local function reply(source, message)
    if source == 0 then
        return lib.print.info(message)
    end

    TriggerClientEvent('chat:addMessage', source, { args = { 'hopouts', message } })
end

---@param source Source
---@return boolean
local function guard(source)
    if not isDebugEnabled() then
        reply(source, 'Hopouts debug commands are off. Set `hopouts:debug 1` in server.cfg.')

        return false
    end

    return true
end

lib.addCommand('hopstart', {
    help = 'Start a hopouts match with everyone online',
    params = {
        { name = 'map', type = 'string', help = 'map id', optional = true },
        { name = 'rounds', type = 'number', help = 'rounds to win', optional = true },
    },
    restricted = 'group.admin',
}, function(source, args)
    if not guard(source) then return end

    local mapId = args.map or next(Hopouts.maps)

    ---@type { source: Source }[]
    local players = {}

    for _, playerSource in ipairs(core:GetPlayerSources()) do
        players[#players + 1] = { source = playerSource }
    end

    if #players == 0 then
        return reply(source, 'Nobody is loaded.')
    end

    local matchId, err = Hopouts.createMatch({
        mapId = mapId,
        players = players,
        roundsToWin = args.rounds and math.floor(args.rounds) or nil,
    })

    reply(source, matchId and ('Started match %s on %s.'):format(matchId, mapId) or ('Failed: %s'):format(err))
end)

lib.addCommand('hopstop', {
    help = 'End the match you are in',
    restricted = 'group.admin',
}, function(source)
    if not guard(source) then return end

    local match = Hopouts.getMatchForPlayer(source --[[@as Source]])

    if not match then
        return reply(source, 'You are not in a match.')
    end

    Hopouts.destroyMatch(match.id, 'ended by staff')

    reply(source, 'Match ended.')
end)

lib.addCommand('hopstate', {
    help = 'Force the match you are in into a state',
    params = {
        { name = 'state', type = 'string', help = 'lobby|warmup|preround|live|roundend|switchsides|matchend' },
    },
    restricted = 'group.admin',
}, function(source, args)
    if not guard(source) then return end

    local match = Hopouts.getMatchForPlayer(source --[[@as Source]])

    if not match then
        return reply(source, 'You are not in a match.')
    end

    if not Hopouts.states[args.state] then
        return reply(source, ('Unknown state "%s".'):format(args.state))
    end

    Hopouts.setState(match, args.state, 10000)

    reply(source, ('State -> %s.'):format(args.state))
end)

lib.addCommand('hopinfo', {
    help = 'Print what the engine thinks is happening',
    restricted = 'group.admin',
}, function(source)
    local match = Hopouts.getMatchForPlayer(source --[[@as Source]])

    if not match then
        return reply(source, 'You are not in a match.')
    end

    reply(source, ('match %s | map %s | state %s (%sms left) | round %s | scores %s | swapped %s'):format(
        match.id,
        match.map.id,
        match.state,
        Hopouts.getStateRemaining(match),
        match.round,
        json.encode(match.scores),
        tostring(match.swapped)
    ))
end)

lib.addCommand('hopdouble', {
    help = 'Open the run-it-back prompt for the match you are in',
    restricted = 'group.admin',
}, function(source)
    if not guard(source) then return end

    local match = Hopouts.getMatchForPlayer(source --[[@as Source]])

    if not match then
        return reply(source, 'You are not in a match.')
    end

    Hopouts.startRequestDouble(match)
end)

lib.addCommand('hopmaps', {
    help = 'List the maps the engine can load',
    restricted = 'group.admin',
}, function(source)
    local maps = Hopouts.getVotableMaps()
    local names = {}

    for index = 1, #maps do
        names[index] = maps[index].id
    end

    reply(source, #names > 0 and table.concat(names, ', ') or 'No maps defined in data/maps.lua.')
end)
