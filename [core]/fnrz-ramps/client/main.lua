local active, spectator, arenaId, status = false, false, nil, nil
local origin, oldInvincible, generation = nil, false, 0
local function notify(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end
local function teleport(position)
    local ped = PlayerPedId()
    SetEntityCoords(ped, position.x, position.y, position.z, false, false, false, true)
    SetEntityHeading(ped, position.w)
end
local function remember()
    generation = generation + 1
    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    origin = { x = p.x, y = p.y, z = p.z, w = GetEntityHeading(ped) }
    oldInvincible = GetPlayerInvincible(PlayerId())
end
local function cleanup(position)
    FreezeEntityPosition(PlayerPedId(), false)
    SetPlayerInvincible(PlayerId(), oldInvincible)
    if position or origin then teleport(position or origin) end
    active, spectator, arenaId, status, origin = false, false, nil, nil, nil
end
RegisterNetEvent('ramps:client:notify', notify)
RegisterNetEvent('ramps:client:enterMatch', function(id, size, team)
    remember()
    active, spectator, arenaId = true, false, id
    SendNUIMessage({ action = 'show', mode = size == 1 and '1V1' or '2V2', arena = Config.Arenas[id].name, team = team })
    notify(team == 1 and 'You are on BLUE team.' or 'You are on RED team.')
end)
RegisterNetEvent('ramps:client:startRound', function(id, slot)
    if not active or id ~= arenaId then return end
    status = 'countdown'
    FreezeEntityPosition(PlayerPedId(), true)
    teleport(Config.Arenas[id].spawns[slot])
end)
RegisterNetEvent('ramps:client:matchState', function(state)
    if not active and not spectator then return end
    status = state.status
    if active then FreezeEntityPosition(PlayerPedId(), status ~= 'running') end
    SendNUIMessage({ action = 'state', round = state.round, scores = state.scores, status = state.status, time = state.time })
end)
RegisterNetEvent('ramps:client:matchFinished', function(winner, scores, position)
    if not active and not spectator then return end
    cleanup(position)
    generation = generation + 1
    local token = generation
    SendNUIMessage({ action = 'finish', winner = winner, scores = scores })
    SetTimeout(6000, function()
        if token == generation then SendNUIMessage({ action = 'hide' }) end
    end)
end)
RegisterNetEvent('ramps:client:spectator', function(enabled, id, size)
    if not enabled then cleanup() SendNUIMessage({ action = 'hide' }) return end
    remember()
    active, spectator, arenaId = false, true, id
    teleport(Config.Arenas[id].spectator)
    FreezeEntityPosition(PlayerPedId(), true)
    SetPlayerInvincible(PlayerId(), true)
    SendNUIMessage({ action = 'show', mode = 'WATCHING '..size..'V'..size, arena = Config.Arenas[id].name })
end)
RegisterCommand('rampsfinish', function()
    if active and status == 'running' then TriggerServerEvent('ramps:server:finish') end
end)
CreateThread(function()
    while true do
        Wait(500)
        if active and status == 'running' and arenaId then
            if #(GetEntityCoords(PlayerPedId()) - Config.Arenas[arenaId].finish) <= Config.Match.finishRadius then
                TriggerServerEvent('ramps:server:finish')
            end
        end
    end
end)
CreateThread(function()
    while true do
        if spectator then
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 23, true)
            Wait(0)
        else Wait(500) end
    end
end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if active or spectator then cleanup() end
    SetNuiFocus(false, false)
end)
