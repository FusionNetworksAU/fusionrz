local isVisible = false

---@type { screenshake: boolean, recoil: boolean }
local settings = {
    screenshake = false,
    recoil = false,
}

local function applyCombatSettings()
    exports.ui:setWindyScreenshake(settings.screenshake)
    exports.ui:setWindyRecoil(settings.recoil)
end

---@param visible boolean
local function setSnsMenuVisible(visible)
    if not visible and not isVisible then
        return
    end

    isVisible = visible == true

    SendNUIMessage({ action = 'setSnsMenuVisible', data = isVisible })
    SetNuiFocus(isVisible, isVisible)

    if isVisible then
        SendNUIMessage({ action = 'setSnsMenuSettings', data = settings })
    end
end

exports('setSnsMenuVisible', setSnsMenuVisible)

---@param data { screenshake?: boolean, recoil?: boolean }
local function setSnsMenuSettings(data)
    if type(data) ~= 'table' then
        return
    end

    if data.screenshake ~= nil then
        settings.screenshake = not not data.screenshake
    end

    if data.recoil ~= nil then
        settings.recoil = not not data.recoil
    end

    applyCombatSettings()
    SendNUIMessage({ action = 'setSnsMenuSettings', data = settings })
end

exports('setSnsMenuSettings', setSnsMenuSettings)

exports('getSnsMenuSettings', function()
    return {
        screenshake = settings.screenshake,
        recoil = settings.recoil,
    }
end)

exports('isSnsMenuVisible', function()
    return isVisible
end)

exports('applySnsCombatSettings', applyCombatSettings)

exports('clearSnsCombatSettings', function()
    exports.ui:clearWindyEffects()
end)

RegisterNUICallback('closeSnsMenu', function(_, cb)
    cb(1)
    setSnsMenuVisible(false)
end)

---@param data { screenshake?: boolean, recoil?: boolean }
RegisterNUICallback('setSnsSetting', function(data, cb)
    if type(data) ~= 'table' then
        cb(false)
        return
    end

    setSnsMenuSettings(data)
    cb(true)
end)

RegisterNUICallback('leaveSns', function(_, cb)
    cb(1)

    setSnsMenuVisible(false)

    local left = GetResourceState('sns') == 'started' and exports.sns:leave()
    if not left then
        exports.ui:notify({ type = 'error', text = 'Failed to leave Shooting & Scenes' })
    end
end)
