local levelsConfig = require '@levels.config.shared' ---@type LevelsSharedConfig

local playerState = LocalPlayer.state

---@type CareerLevelState?
local careerLevel

local function sendCareerLevel()
    SendNUIMessage({ action = 'setCareerLevel', data = careerLevel })
end

---@param level integer
---@param xp integer
---@param prestige integer
RegisterNetEvent('levels:client:state', function(level, xp, prestige)
    careerLevel = levelsConfig.buildState(level, xp, prestige)

    if playerState.uisReady then
        sendCareerLevel()
    end
end)

AddEventHandler('uis:onReady', function()
    if careerLevel then
        sendCareerLevel()
    end
end)

---@param data { next: number, seconds: number }?
local function setPrestigeOffer(data)
    SendNUIMessage({ action = 'setPrestigeOffer', data = data or false })
    SetNuiFocus(data ~= nil, data ~= nil)
end

exports('setPrestigeOffer', setPrestigeOffer)

---@param prestige number
local function setPrestigeSuccess(prestige)
    SendNUIMessage({ action = 'setPrestigeSuccess', data = prestige })
end

exports('setPrestigeSuccess', setPrestigeSuccess)

RegisterNUICallback('prestigeAnswer', function(confirm, cb)
    cb(1)
    SetNuiFocus(false, false)
    TriggerEvent('ui:prestigeAnswer', confirm == true)
end)
