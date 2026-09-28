local ui = exports.ui
local playerState = LocalPlayer.state

local warningTimer = nil

---@param count integer
local function setTotalAdminsOnline(count)
    SendNUIMessage({ action = 'setTotalAdminsOnline', data = count })
end

---@param visible boolean
local function setAdminMenuVisible(visible)
    SendNUIMessage({ action = 'setAdminMenuVisible', data = visible })
    SetNuiFocus(visible, visible)

    if visible then
        lib.callback('admin:server:subscribeActiveAdmins', false, setTotalAdminsOnline, 'admin')
    else
        TriggerServerEvent('admin:server:unsubscribeActiveAdmins', 'admin')
    end
end

exports('setAdminMenuVisible', setAdminMenuVisible)

---@param visible boolean
local function setWarningVisible(visible)
    SendNUIMessage({ action = 'setWarningVisible', data = visible })
end

exports('setWarningVisible', setWarningVisible)

---@param data table
local function setWarningData(data)
    SendNUIMessage({ action = 'setWarningData', data = data })
end

exports('setWarningData', setWarningData)

RegisterNUICallback('closeAdminMenu', function(_, cb)
    cb(1)

    setAdminMenuVisible(false)
end)

---@param data table
RegisterNUICallback('warnPlayer', function(data, cb)
    local success = lib.callback.await('admin:server:warnPlayer', false, data)

    cb(success)
end)

---@param message string
RegisterNUICallback('sendStaffChatMessage', function(message, cb)
    local success = lib.callback.await('admin:server:sendStaffChatMessage', false, message)

    cb(success)
end)

---@param targetId number
RegisterNUICallback('getSelectedPlayerInfo', function(targetId, cb)
    local data = lib.callback.await('admin:server:getSelectedPlayerInfo', false, targetId)

    cb(data)
end)

---@param targetId number
RegisterNUICallback('getSelectedDisconnectedInfo', function(targetId, cb)
    local data = lib.callback.await('admin:server:getSelectedDisconnectedInfo', false, targetId)

    cb(data)
end)

---@param targetId number
RegisterNUICallback('spectatePlayer', function(targetId, cb)
    TriggerServerEvent('admin:server:spectateStart', targetId)
    cb(1)
end)

---@param targetId number
RegisterNUICallback('gotoPlayer', function(targetId, cb)
    local success, resp = lib.callback.await('admin:server:gotoPlayer', false, targetId)

    ui:notify({ type = success and 'success' or 'error', text = resp })

    cb(1)
end)

---@param targetId number
RegisterNUICallback('bringPlayer', function(targetId, cb)
    local success, resp = lib.callback.await('admin:server:bringPlayer', false, targetId)

    ui:notify({ type = success and 'success' or 'error', text = resp })

    cb(1)
end)

---@param targetId number
RegisterNUICallback('revivePlayer', function(targetId, cb)
    local success, resp = lib.callback.await('admin:server:revivePlayer', false, targetId)

    ui:notify({ type = success and 'success' or 'error', text = resp })

    cb(1)
end)

---@param targetId number
RegisterNUICallback('healPlayer', function(targetId, cb)
    local success, resp = lib.callback.await('admin:server:healPlayer', false, targetId)

    ui:notify({ type = success and 'success' or 'error', text = resp })

    cb(1)
end)

---@param targetId number
RegisterNUICallback('freezePlayer', function(targetId, cb)
    local success, resp = lib.callback.await('admin:server:freezePlayer', false, targetId)

    ui:notify({ type = success and 'success' or 'error', text = resp })

    cb(1)
end)

---@param targetId number
RegisterNUICallback('killPlayer', function(targetId, cb)
    local success, resp = lib.callback.await('admin:server:killPlayer', false, targetId)

    ui:notify({ type = success and 'success' or 'error', text = resp })

    cb(1)
end)

---@param data table
RegisterNUICallback('kickPlayer', function(data, cb)
    local success, err = lib.callback.await('admin:server:kickPlayer', false, data)

    if not success then
        ui:notify({ type = 'error', text = err or 'Something went wrong' })
    else
        ui:notify({ type = 'success', text = 'Player Kicked' })
    end

    cb(success)
end)

---@param data table
RegisterNUICallback('banPlayer', function(data, cb)
    local success, err = lib.callback.await('admin:server:banPlayer', false, data)

    if not success then
        ui:notify({ type = 'error', text = err or 'Something went wrong' })
    else
        ui:notify({ type = 'success', text = 'Player Banned' })
    end

    cb(success)
end)

RegisterNUICallback('getConnectedPlayers', function(_, cb)
    local connected = lib.callback.await('admin:server:getConnected', false)
    local list = {}

    for k, v in pairs(connected) do
        list[#list + 1] = v
    end

    cb(list)
end)

RegisterNUICallback('getDisconnectedPlayers', function(_, cb)
    local disconnected = lib.callback.await('admin:server:getDisconnected', false)

    cb(disconnected)
end)

RegisterNUICallback('getAllAdminReports', function(_, cb)
    local reports = lib.callback.await('admin:server:getAllAdminReports', false)

    cb(reports)
end)

---@param reportId integer
RegisterNUICallback('getAdminReportMessages', function(reportId, cb)
    local data = lib.callback.await('admin:server:fetchReportMessages', false, reportId)

    cb(data)
end)

RegisterNUICallback('getAllLiveGames', function(_, cb)
    local games = lib.callback.await('ui:server:getAllLiveGames', false)

    cb(games)
end)

---@param data { reportId: number, text: string }
RegisterNUICallback('sendAdminReportMessage', function(data, cb)
    local success = lib.callback.await('admin:server:sendAdminReportMessage', false, data)

    cb(success)
end)

---@param gameId integer
RegisterNUICallback('toggleGameFreeze', function(gameId, cb)
    local isFrozen, success, message = lib.callback.await('ui:server:toggleGameFreeze', false, gameId)

    if message then
        ui:notify({
            type = success and 'success' or 'error',
            text = message
        })
    end

    cb(isFrozen)
end)

---@param gameId integer
RegisterNUICallback('viewLiveGame', function(gameId, cb)
    local success, err = lib.callback.await('ui:server:viewLiveGame', false, gameId)

    if not success then
        lib.print.error('Unable to view live game:', err)
        ui:notify({ type = 'error', text = err or 'Something went wrong' })
    end

    cb(success)
end)

---@param gameId integer
RegisterNUICallback('leaveLiveGame', function(gameId, cb)
    local success, err = lib.callback.await('ui:server:leaveLiveGame', false, gameId)

    if not success then
        lib.print.error('Unable to leave live game:', err)
        ui:notify({ type = 'error', text = err or 'Something went wrong' })
    end

    cb(success)
end)

---@param gameId integer
RegisterNUICallback('getLiveGamePlayers', function(gameId, cb)
    local data = lib.callback.await('ui:server:getLiveGamePlayers', false, gameId)

    cb(data)
end)

---@param reason string
---@param adminUsername string
RegisterNetEvent('admin:warnPlayer', function(reason, adminUsername)
    setWarningData({
        description = reason,
        adminUsername = adminUsername,
    })

    setWarningVisible(true)

    if warningTimer then
        warningTimer:restart()
        return
    end

    warningTimer = lib.timer(7500, function()
        setWarningVisible(false)
        warningTimer = nil
     end, true)
end)

---@param player table
RegisterNetEvent('admin:playerJoined', function(player)
    SendNUIMessage({ action = 'playerJoined', data = player })
end)

---@param userId integer
---@param player? table
RegisterNetEvent('admin:playerDropped', function(userId, player)
    SendNUIMessage({
        action = 'playerDropped',
        data = {
            userId = userId,
            player = player
        }
    })
end)

---@param userIds number[]
RegisterNetEvent('admin:removeDisconnected', function(userIds)
    SendNUIMessage({ action = 'removeDisconnected', data = userIds })
end)

---@param message table
RegisterNetEvent('admin:addStaffChatMessage', function(message)
    SendNUIMessage({ action = 'addStaffChatMessage', data = message })
end)

---@param messages table[]
RegisterNetEvent('admin:setStaffChatMessages', function(messages)
    while not playerState.uisReady do
        Wait(100)
    end

    SendNUIMessage({ action = 'setStaffChatMessages', data = messages })
end)

RegisterNetEvent('admin:setActiveAdmins', setTotalAdminsOnline)

---@param gameId integer
local function removeViewingGameById(gameId)
    SendNUIMessage({ action = 'removeViewingGameById', data = gameId })
end

exports('removeViewingGameById', removeViewingGameById)
