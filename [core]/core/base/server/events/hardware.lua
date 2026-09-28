---Hardware + alt-account reporting.
---
---The client volunteers this, so none of it is trusted as fact: it is
---recorded and logged for a human to look at, never acted on automatically.
---What the server does trust is user_identifiers, which is built from
---identifiers the platform supplies.

local MAX_REPORTED_IDS = 50

Core.guardEvent('core:server:reportHardware', {
    burst = 2,
    rate = 0.1,
    args = { 'table' },
}, function(player, report)
    if type(report.fingerprint) ~= 'string' or #report.fingerprint > 128 then
        return
    end

    local ok, err = pcall(Core.db.recordHardware, player.userId, report)

    if not ok then
        lib.print.error(('[core] hardware record failed for %s: %s'):format(player.userId, err))
    end
end)

---ui/client/uis/hardware.lua sends the other user ids it has seen on this
---machine, with its own id already filtered out.
Core.guardEvent('core:validateUserIds', {
    burst = 2,
    rate = 0.1,
    args = { 'table' },
}, function(player, userIds)
    ---@type integer[]
    local parsed = {}

    for index = 1, math.min(#userIds, MAX_REPORTED_IDS) do
        local userId = tonumber(userIds[index])

        if userId then
            parsed[#parsed + 1] = math.floor(userId)
        end
    end

    if #parsed == 0 then
        return
    end

    local ok, usernames = pcall(Core.db.getUsernames, parsed)

    if not ok then
        return lib.print.error(('[core] username lookup failed: %s'):format(usernames))
    end

    ---@type string[]
    local known = {}

    for userId, username in pairs(usernames) do
        known[#known + 1] = ('%s (%s)'):format(username, userId)
    end

    if #known == 0 then
        return
    end

    Core.log('connections', ('%s (%s) shares a machine with: %s'):format(
        player.username, player.userId, table.concat(known, ', ')
    ))

    TriggerEvent('core:server:onAltAccountsSeen', player.source, parsed)
end)

---@param source Source
---@return integer[]
exports('GetLinkedUserIds', function(source)
    local player = Core.getPlayer(source)

    if not player then
        return {}
    end

    local ok, linked = pcall(Core.db.getLinkedUserIds, player.userId)

    return ok and linked or {}
end)
