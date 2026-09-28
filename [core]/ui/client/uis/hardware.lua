local core = exports.core

---@param data HardwareReport
RegisterNUICallback('receivedAccountInfo', function(data, cb)
    cb(1)

    core:ReportHardware(data)
end)

---@param data string[]
RegisterNUICallback('receivedUserInfo', function(data, cb)
    cb(1)

    local currentUserId = tostring(PlayerData.userId)

    ---@type string[]
    local userIds = {}

    for _, userId in pairs(data) do
        if userId ~= currentUserId then
            userIds[#userIds + 1] = userId
        end
    end

    if #userIds == 0 then
        return
    end

    TriggerServerEvent('core:validateUserIds', userIds)
end)
