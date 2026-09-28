---@param data table
local function setBattlepassPlayerData(data)
    SendNUIMessage({ action = 'setBattlepassPlayerData', data = data })
end

exports('setBattlepassPlayerData', setBattlepassPlayerData)

---@param data table
local function setBattlepassPlayerMissions(data)
    SendNUIMessage({ action = 'setBattlepassPlayerMissions', data = data })
end

exports('setBattlepassPlayerMissions', setBattlepassPlayerMissions)

---@param data table
local function setBattlepassLevels(data)
    SendNUIMessage({ action = 'setBattlepassLevels', data = data })
end

exports('setBattlepassLevels', setBattlepassLevels)

---@param cb function
---@return boolean
local function canUseBattlepass(cb)
    if IsRankedMenuVisible() or (IsPauseMenuVisible and IsPauseMenuVisible()) then
        return true
    end

    cb(false)

    return false
end

---@param cb function
RegisterNUICallback('battlepassOpened', function(_, cb)
    if not canUseBattlepass(cb) then
        return
    end

    TriggerEvent('ui:battlepassOpened')
    cb(true)
end)

RegisterNUICallback('purchaseBattlepass', function(_, cb)
    if not canUseBattlepass(cb) then
        return
    end

    local success, failReason = lib.callback.await('battlepass:server:purchasePass', false)

    if not success then
        exports.ui:notify({ type = 'error', text = failReason or 'Something went wrong' })
    end

    cb(success)
end)

---@param data { targetLevel: integer }
---@param cb function
RegisterNUICallback('upgradeBattlepassLevel', function(data, cb)
    if not canUseBattlepass(cb) then
        return
    end

    local targetLevel = tonumber(data?.targetLevel)
    if not targetLevel then
        exports.ui:notify({ type = 'error', text = 'Invalid battlepass level' })
        cb(false)
        return
    end

    local success, failReason = lib.callback.await('battlepass:server:upgradeLevel', false, targetLevel)

    if not success then
        exports.ui:notify({ type = 'error', text = failReason or 'Something went wrong' })
    end

    cb(success)
end)

---@param data { questId: integer }
---@param cb function
RegisterNUICallback('rerollBattlepassMission', function(data, cb)
    if not canUseBattlepass(cb) then
        return
    end

    local questId = tonumber(data?.questId)
    if not questId then
        exports.ui:notify({ type = 'error', text = 'Invalid mission selected' })
        cb(false)
        return
    end

    local success, failReason = lib.callback.await('battlepass:server:rerollQuest', false, questId)

    if not success then
        exports.ui:notify({ type = 'error', text = failReason or 'Something went wrong' })
    end

    cb(success)
end)

---@param data { targetUserId: integer }
---@param cb function
RegisterNUICallback('giftBattlepass', function(data, cb)
    if not canUseBattlepass(cb) then
        return
    end

    local targetUserId = tonumber(data?.targetUserId)
    if not targetUserId then
        exports.ui:notify({ type = 'error', text = 'Invalid friend selected' })
        cb(false)
        return
    end

    local success, failReason = lib.callback.await('battlepass:server:giftPass', false, targetUserId)

    if not success then
        exports.ui:notify({ type = 'error', text = failReason or 'Something went wrong' })
    else
        exports.ui:notify({ type = 'success', text = 'Battlepass gifted' })
    end

    cb(success)
end)