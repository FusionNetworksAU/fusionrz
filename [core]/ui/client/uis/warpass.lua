---@param data table
local function setWarpassPlayerData(data)
    SendNUIMessage({ action = 'setWarpassPlayerData', data = data })
end

exports('setWarpassPlayerData', setWarpassPlayerData)

---@param data table
local function setWarpassLevels(data)
    SendNUIMessage({ action = 'setWarpassLevels', data = data })
end

exports('setWarpassLevels', setWarpassLevels)

---@param cb function
---@return boolean
local function canUseWarpass(cb)
    if IsMenuVisible() then
        return true
    end

    cb(false)

    return false
end

---@param cb function
RegisterNUICallback('warpassOpened', function(_, cb)
    if not canUseWarpass(cb) then
        return
    end

    TriggerEvent('ui:warpassOpened')
    cb(true)
end)

RegisterNUICallback('purchaseWarpass', function(_, cb)
    if not canUseWarpass(cb) then
        return
    end

    local success, failReason = lib.callback.await('warpass:server:purchasePass', false)

    if not success then
        exports.ui:notify({ type = 'error', text = failReason or 'Something went wrong' })
    end

    cb(success)
end)

---@param data { targetUserId: integer }
---@param cb function
RegisterNUICallback('giftWarpass', function(data, cb)
    if not canUseWarpass(cb) then
        return
    end

    local targetUserId = tonumber(data?.targetUserId)
    if not targetUserId then
        exports.ui:notify({ type = 'error', text = 'Invalid friend selected' })
        cb(false)
        return
    end

    local success, failReason = lib.callback.await('warpass:server:giftPass', false, targetUserId)

    if not success then
        exports.ui:notify({ type = 'error', text = failReason or 'Something went wrong' })
    else
        exports.ui:notify({ type = 'success', text = 'War pass gifted' })
    end

    cb(success)
end)

---@param data { targetLevel: integer }
---@param cb function
RegisterNUICallback('upgradeWarpassLevel', function(data, cb)
    if not canUseWarpass(cb) then
        return
    end

    local targetLevel = tonumber(data?.targetLevel)
    if not targetLevel then
        exports.ui:notify({ type = 'error', text = 'Invalid war pass level' })
        cb(false)
        return
    end

    local success, failReason = lib.callback.await('warpass:server:upgradeLevel', false, targetLevel)

    if not success then
        exports.ui:notify({ type = 'error', text = failReason or 'Something went wrong' })
    end

    cb(success)
end)
