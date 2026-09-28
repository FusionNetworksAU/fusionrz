---@param visible boolean
local function setFfaStatsVisible(visible)
    SendNUIMessage({ action = 'setFfaStatsVisible', data = visible })
end

exports('setFfaStatsVisible', setFfaStatsVisible)

---@param data table
local function setFfaStatsPlayers(data)
    SendNUIMessage({ action = 'setFfaStatsPlayers', data = data })
end

exports('setFfaStatsPlayers', setFfaStatsPlayers)

---@param value string
local function setFfaStatsValue(value)
    SendNUIMessage({ action = 'setFfaStatsValue', data = value })
end

exports('setFfaStatsValue', setFfaStatsValue)

---@param maxValue string
local function setFfaStatsMaxValue(maxValue)
    SendNUIMessage({ action = 'setFfaStatsMaxValue', data = maxValue })
end

exports('setFfaStatsMaxValue', setFfaStatsMaxValue)

---@param seconds number | false | nil
local function setFfaStatsTime(seconds)
    SendNUIMessage({ action = 'setFfaStatsTime', data = seconds })
end

exports('setFfaStatsTime', setFfaStatsTime)

---@param visible boolean
local function setFfaWinnersVisible(visible)
    SendNUIMessage({ action = 'setFfaWinnersVisible', data = visible })
end

exports('setFfaWinnersVisible', setFfaWinnersVisible)

---@param data table
local function setFfaWinnersData(data)
    SendNUIMessage({ action = 'setFfaWinnersData', data = data })
end

exports('setFfaWinnersData', setFfaWinnersData)

---@param visible boolean
local function setFfaMapSelectVisible(visible)
    SendNUIMessage({ action = 'setFfaMapSelectVisible', data = visible })
    SetNuiFocus(visible, visible)

    if visible then TriggerScreenblurFadeIn(0) else TriggerScreenblurFadeOut(0) end
end

exports('setFfaMapSelectVisible', setFfaMapSelectVisible)

---@param data table
local function setFfaMapSelectMaps(data)
    SendNUIMessage({ action = 'setFfaMapSelectMaps', data = data })
end

exports('setFfaMapSelectMaps', setFfaMapSelectMaps)

---@param seconds number
local function setFfaMapSelectTime(seconds)
    SendNUIMessage({ action = 'setFfaMapSelectTime', data = seconds })
end

exports('setFfaMapSelectTime', setFfaMapSelectTime)

---@param data table
local function setFfaMapSelectVotes(data)
    SendNUIMessage({ action = 'setFfaMapSelectVotes', data = data })
end

exports('setFfaMapSelectVotes', setFfaMapSelectVotes)

---@param name string
RegisterNUICallback('submitMapVote', function(name, cb)
    local success = lib.callback.await('gamemodes:server:submitMapVote', false, name)

    cb(success)
end)

RegisterNUICallback('ffaReturnToLobby', function(_, cb)
    ExecuteCommand('leave')
    cb(true)
end)