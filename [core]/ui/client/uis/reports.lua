local playerState = LocalPlayer.state

local isVisible = false

exports('isReportsMenuVisible', function()
    return isVisible
end)

---@param visible boolean
local function setReportsMenuVisible(visible)
    SendNUIMessage({ action = 'setReportsMenuVisible', data = visible })
    SetNuiFocus(visible, visible)
    isVisible = visible

    if visible then
        lib.callback('admin:server:subscribeActiveAdmins', false, function(count)
            SendNUIMessage({ action = 'setTotalAdminsOnline', data = count })
        end, 'reports')
    else
        TriggerServerEvent('admin:server:unsubscribeActiveAdmins', 'reports')
    end
end

exports('setReportsMenuVisible', setReportsMenuVisible)

---@param data table
local function addMyReportMessage(data)
    SendNUIMessage({ action = 'addMyReportMessage', data = data })
end

exports('addMyReportMessage', addMyReportMessage)

---@param data table
local function addAdminReportMessage(data)
    SendNUIMessage({ action = 'addAdminReportMessage', data = data })
end

exports('addAdminReportMessage', addAdminReportMessage)

---@param data table
local function addMyReport(data)
    SendNUIMessage({ action = 'addMyReport', data = data })
end

exports('addMyReport', addMyReport)

---@param data table
local function addAdminReport(data)
    SendNUIMessage({ action = 'addAdminReport', data = data })
end

exports('addAdminReport', addAdminReport)

---@param data table
local function markMyReportAsResolved(data)
    SendNUIMessage({ action = 'markMyReportAsResolved', data = data })
end

exports('markMyReportAsResolved', markMyReportAsResolved)

---@param data table
local function markAdminReportAsResolved(data)
    SendNUIMessage({ action = 'markAdminReportAsResolved', data = data })
end

exports('markAdminReportAsResolved', markAdminReportAsResolved)

---@param reports table[]
RegisterNetEvent('admin:setMyReports', function(reports)
    while not playerState.uisReady do
        Wait(100)
    end

    SendNUIMessage({ action = 'setMyReports', data = reports })
end)

RegisterNUICallback('closeReportMenu', function(_, cb)
    cb(1)

    setReportsMenuVisible(false)
end)

---@param data { playerId?: string, reason: string, description: string }
RegisterNUICallback('submitReport', function(data, cb)
    local success = lib.callback.await('admin:server:submitReport', false, data)

    cb(success)
end)

---@param data { reportId: number, text: string }
RegisterNUICallback('sendReportMessage', function(data, cb)
    local success = lib.callback.await('admin:server:sendReportMessage', false, data)

    cb(success)
end)

---@param reportId number
RegisterNUICallback('markAdminReportAsResolved', function(reportId, cb)
    local success = lib.callback.await('admin:server:markReportAsResolved', false, reportId)

    cb(success)
end)
