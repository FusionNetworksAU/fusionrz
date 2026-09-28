local playerState = LocalPlayer.state

---@type integer|nil
local cachedTotalPlayers = nil

local function sendTotalPlayers()
    SendNUIMessage({ action = 'setLeaderboardData', data = { totalPlayers = cachedTotalPlayers } })
end

---@param totalPlayers integer
RegisterNetEvent('uis:setLeaderboardTotalPlayers', function(totalPlayers)
    cachedTotalPlayers = totalPlayers

    if playerState.uisReady then
        sendTotalPlayers()
    end
end)

AddEventHandler('uis:onReady', function()
    if cachedTotalPlayers then
        sendTotalPlayers()
    end
end)

---@param data table
RegisterNUICallback('getLeaderboardPlayers', function(data, cb)
    local result = lib.callback.await('uis:server:getLeaderboardPlayers', false, data)

    cb(result)
end)

---@param data table
RegisterNUICallback('getLeaderboardGangs', function(data, cb)
    local result = lib.callback.await('uis:server:getLeaderboardGangs', false, data)

    cb(result)
end)
