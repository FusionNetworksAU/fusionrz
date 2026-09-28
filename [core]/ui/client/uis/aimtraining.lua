local playerState = LocalPlayer.state

local aimtraining = exports.aimtraining

local isLeaderboardVisible = false

---@param isVisible boolean
local function setAimTrainingVisible(isVisible)
    SendNUIMessage({ action = 'setAimTrainingVisible', data = isVisible })
end

exports('setAimTrainingVisible', setAimTrainingVisible)

---@param data table
local function setAimTrainingData(data)
    SendNUIMessage({ action = 'setAimTrainingData', data = data })
end

exports('setAimTrainingData', setAimTrainingData)

---@param isVisible boolean
local function setAimTrainingLeaderboardVisible(isVisible)
    SendNUIMessage({ action = 'setAimTrainingLeaderboardVisible', data = isVisible })
    SetNuiFocus(isVisible, isVisible)
    isLeaderboardVisible = isVisible
end

exports('setAimTrainingLeaderboardVisible', setAimTrainingLeaderboardVisible)

---@param data table
local function setAimTrainingLeaderboardData(data)
    SendNUIMessage({ action = 'setAimTrainingLeaderboardData', data = data })
end

exports('setAimTrainingLeaderboardData', setAimTrainingLeaderboardData)

local function sendMapsToUI()
     SendNUIMessage({
        action = 'setAimTrainingCategories',
        data = {
            {
                label = 'General',
                key = 'general'
            }
        },
    })

    SendNUIMessage({
        action = 'setAimTrainingMaps',
        data = aimtraining:getMapsForUI(),
    })
end

RegisterNUICallback('enterAimTrainingMap', function(data, cb)
    cb(1)
    if IsMenuVisible() then
        aimtraining:enterMode(data.label, data.isTraining)
    end
end)

CreateThread(function()
    while not playerState.uisReady do
        Wait(100)
    end

    if GetResourceState('aimtraining') == 'started' then
        sendMapsToUI()
    end
end)

---@param resourceName string
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'aimtraining' and playerState.uisReady then
        sendMapsToUI()
    end
end)

RegisterNUICallback('closeAimTraining', function(_, cb)
    cb(1)
    if isLeaderboardVisible then
        setAimTrainingLeaderboardVisible(false)
        TriggerServerEvent('aimtraining:stopGame')
    end
end)

RegisterNUICallback('replayAimTraining', function(_, cb)
    cb(1)
    if isLeaderboardVisible then
        setAimTrainingLeaderboardVisible(false)
        TriggerServerEvent('aimtraining:server:resetGame')
    end
end)