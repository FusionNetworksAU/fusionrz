local queues = { [1] = {}, [2] = {} }
local matches, playerMatch, playerSpectating, saved, queuedAt, lastFinish = {}, {}, {}, {}, {}, {}
local nextMatchId = 0
local function valid(src) return src and GetPlayerName(src) ~= nil end
local function notify(src, text)
    if valid(src) then TriggerClientEvent('ramps:client:notify', src, text) end
end
local function removeFromQueue(src)
    for _, queue in pairs(queues) do
        for i = #queue, 1, -1 do if queue[i] == src then table.remove(queue, i) end end
    end
    queuedAt[src] = nil
end
local function remember(src)
    local ped = GetPlayerPed(src)
    if ped == 0 or GetEntityHealth(ped) <= 0 or GetVehiclePedIsIn(ped, false) ~= 0 then
        notify(src, 'You must be alive and on foot.')
        return false
    end
    local p = GetEntityCoords(ped)
    saved[src] = { x = p.x, y = p.y, z = p.z, w = GetEntityHeading(ped), bucket = GetPlayerRoutingBucket(src) }
    return true
end
local function restore(src, winner, scores)
    local origin = saved[src]
    saved[src], playerMatch[src], playerSpectating[src], lastFinish[src] = nil, nil, nil, nil
    if not valid(src) then return end
    if origin then SetPlayerRoutingBucket(src, origin.bucket) end
    TriggerClientEvent('ramps:client:matchFinished', src, winner, scores or {0, 0}, origin)
end
local function sendState(match)
    local state = { round = match.round, scores = match.scores, status = match.status,
        time = math.max(0, (match.deadline or os.time()) - os.time()) }
    for _, src in ipairs(match.players) do TriggerClientEvent('ramps:client:matchState', src, state) end
    for src in pairs(match.spectators) do TriggerClientEvent('ramps:client:matchState', src, state) end
end
local function endMatch(match, winner)
    if not matches[match.id] then return end
    matches[match.id] = nil
    for _, src in ipairs(match.players) do restore(src, winner, match.scores) end
    for src in pairs(match.spectators) do restore(src, winner, match.scores) end
end
local function startRound(match)
    if not matches[match.id] then return end
    match.status = 'countdown'
    match.deadline = os.time() + Config.Match.countdown
    for index, src in ipairs(match.players) do
        TriggerClientEvent('ramps:client:startRound', src, match.arena, index, match.round)
    end
    sendState(match)
end
local function finishRound(match, team)
    -- Lock the round before changing scores so simultaneous finish requests cannot score twice.
    if match.status ~= 'running' then return end
    match.status = 'intermission'
    if team then
        match.scores[team] = match.scores[team] + 1
        if match.scores[team] >= Config.Match.roundsToWin then return endMatch(match, team) end
        match.round = match.round + 1
    end
    match.deadline = os.time() + Config.Match.intermission
    sendState(match)
end
local function teamOf(match, src)
    for index, player in ipairs(match.players) do
        if player == src then return index <= match.size and 1 or 2 end
    end
end
local function leave(src)
    removeFromQueue(src)
    local match = matches[playerMatch[src]]
    if match then return endMatch(match, 3 - teamOf(match, src)) end
    match = matches[playerSpectating[src]]
    if match then match.spectators[src] = nil end
    if saved[src] then restore(src) end
end
local function createMatch(size, players)
    nextMatchId = nextMatchId + 1
    local match = { id = nextMatchId, size = size, players = players, spectators = {},
        arena = ((nextMatchId - 1) % #Config.Arenas) + 1,
        bucket = Config.Match.bucketBase + nextMatchId, round = 1, scores = {0, 0} }
    matches[match.id] = match
    SetRoutingBucketPopulationEnabled(match.bucket, false)
    for index, src in ipairs(players) do
        playerMatch[src] = match.id
        SetPlayerRoutingBucket(src, match.bucket)
        TriggerClientEvent('ramps:client:enterMatch', src, match.arena, size, index <= size and 1 or 2)
    end
    startRound(match)
end
local function joinQueue(src, size)
    if not valid(src) then return end
    if playerMatch[src] or playerSpectating[src] then return notify(src, 'Leave your current match or spectator session first.') end
    removeFromQueue(src)
    queues[size][#queues[size] + 1] = src
    queuedAt[src] = os.time()
    notify(src, ('Queued for %dv%d ramps.'):format(size, size))
    local queue = queues[size]
    for i = #queue, 1, -1 do
        local player = queue[i]
        local ped = valid(player) and GetPlayerPed(player) or 0
        if ped == 0 or GetEntityHealth(ped) <= 0 or GetVehiclePedIsIn(ped, false) ~= 0 then
            table.remove(queue, i)
            queuedAt[player] = nil
            notify(player, 'Removed from queue: you must be alive and on foot.')
        end
    end
    while #queue >= size * 2 do
        local players = {}
        for i = 1, size * 2 do
            local player = table.remove(queue, 1)
            queuedAt[player] = nil
            remember(player)
            players[i] = player
        end
        createMatch(size, players)
    end
end
RegisterCommand(Config.Commands.duel, function(src) if src > 0 then joinQueue(src, 1) end end)
RegisterCommand(Config.Commands.teams, function(src) if src > 0 then joinQueue(src, 2) end end)
RegisterCommand(Config.Commands.leave, function(src)
    if src > 0 then leave(src) notify(src, 'You left ramps.') end
end)
RegisterCommand(Config.Commands.spectate, function(src, args)
    if not valid(src) or src <= 0 then return end
    if playerMatch[src] or playerSpectating[src] then return notify(src, 'Leave your current session first.') end
    local id = tonumber(args[1]) or next(matches)
    local match = id and matches[id]
    if not match then return notify(src, 'No active match to watch.') end
    if not remember(src) then return end
    removeFromQueue(src)
    playerSpectating[src] = id
    match.spectators[src] = true
    SetPlayerRoutingBucket(src, match.bucket)
    TriggerClientEvent('ramps:client:spectator', src, true, match.arena, match.size)
    sendState(match)
    notify(src, 'Watching match '..id..'. Use /'..Config.Commands.leave..' to exit.')
end)
RegisterNetEvent('ramps:server:finish', function()
    local src = source
    local now = GetGameTimer()
    if lastFinish[src] and now - lastFinish[src] < 500 then return end
    local match = matches[playerMatch[src]]
    if not match or match.status ~= 'running' then return end
    lastFinish[src] = now
    local ped = GetPlayerPed(src)
    if ped == 0 or GetEntityHealth(ped) <= 0 or GetPlayerRoutingBucket(src) ~= match.bucket then return end
    if #(GetEntityCoords(ped) - Config.Arenas[match.arena].finish) > Config.Match.finishRadius then return end
    finishRound(match, teamOf(match, src))
end)
AddEventHandler('playerDropped', function()
    local src = source
    leave(src)
    saved[src], lastFinish[src] = nil, nil
end)
CreateThread(function()
    while true do
        Wait(500)
        local now = os.time()
        for src, timestamp in pairs(queuedAt) do
            if now - timestamp >= Config.Match.queueTimeout then
                removeFromQueue(src)
                notify(src, 'Ramps queue timed out.')
            end
        end
        for _, match in pairs(matches) do
            for src in pairs(match.spectators) do
                local ped = GetPlayerPed(src)
                local deck = Config.Arenas[match.arena].spectator
                if ped ~= 0 and #(GetEntityCoords(ped) - vec3(deck.x, deck.y, deck.z)) > 3.0 then
                    SetEntityCoords(ped, deck.x, deck.y, deck.z, false, false, false, false)
                end
            end
            local eliminated = { true, true }
            for index, src in ipairs(match.players) do
                local ped = GetPlayerPed(src)
                local team = index <= match.size and 1 or 2
                if ped ~= 0 and GetEntityHealth(ped) > 0 then eliminated[team] = false end
            end
            -- This race resource does not replace a server's death/respawn system.
            -- End the match on a team wipe rather than trap dead players in new rounds.
            if eliminated[1] or eliminated[2] then
                endMatch(match, eliminated[1] and (eliminated[2] and 0 or 2) or 1)
            end
            if matches[match.id] and now >= match.deadline then
                if match.status == 'countdown' then
                    match.status = 'running'
                    match.deadline = now + Config.Match.roundTime
                elseif match.status == 'running' then
                    -- A timeout is a draw: replay this round rather than award an arbitrary winner.
                    finishRound(match)
                elseif match.status == 'intermission' then startRound(match) end
            end
            if matches[match.id] then sendState(match) end
        end
    end
end)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for src, origin in pairs(saved) do
        if valid(src) then
            SetPlayerRoutingBucket(src, origin.bucket)
            local ped = GetPlayerPed(src)
            if ped ~= 0 then SetEntityCoords(ped, origin.x, origin.y, origin.z, false, false, false, false) end
        end
    end
end)
