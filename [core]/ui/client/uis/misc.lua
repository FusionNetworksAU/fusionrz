---@param visible boolean
local function setGamemodePreviewVisible(visible)
    SendNUIMessage({ action = 'setGamemodePreviewVisible', data = visible })
    SetNuiFocus(visible, visible)
end

exports('setGamemodePreviewVisible', setGamemodePreviewVisible)

---@param data table
local function setGamemodePreviewData(data)
    SendNUIMessage({ action = 'setGamemodePreviewData', data = data })
end

exports('setGamemodePreviewData', setGamemodePreviewData)

---@param seconds number
local function setCountdownValue(seconds)
    SendNUIMessage({ action = 'setCountdownValue', data = seconds })
end

exports('setCountdownValue', setCountdownValue)

---@param data table
local function notify(data)
    if not data.duration then
        data.duration = 3000
    end

    SendNUIMessage({ action = 'notify', data = data })
end

exports('notify', notify)
RegisterNetEvent('uis:notify', notify)

RegisterNUICallback('closeGamemodePreview', function(_, cb)
    cb(1)

    TriggerEvent('uis:closeGamemodePreview')
end)

RegisterNUICallback('enterGamemode', function(_, cb)
    cb(1)

    TriggerEvent('uis:enterGamemode')
end)

---@param seconds number
local function setNamedCountdownValue(seconds)
    SendNUIMessage({ action = 'setNamedCountdownValue', data = seconds })
end

exports('setNamedCountdownValue', setNamedCountdownValue)

---@param data table
local function setNamedCountdownData(data)
    SendNUIMessage({ action = 'setNamedCountdownData', data = data })
end

exports('setNamedCountdownData', setNamedCountdownData)