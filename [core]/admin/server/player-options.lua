---Actions a staff member takes against another player.
---
---Every one re-checks the ace itself. The UI expects (success, message) from
---the movement and state actions, and (success, error) from kick and warn --
---the same pair either way, so they all return that.
---
---Anything that can only happen on the target's own client (revive, heal,
---freeze) goes out as an admin:client:* event for the client half to act on.

local core = exports.core

-- --------------------------------------------------------------- movement ----

---@param targetId integer
---@return boolean success
---@return string message
lib.callback.register('admin:server:gotoPlayer', function(source, targetId)
    local targetSource, targetData, err = Admin.gateAndResolve(source, 'goto', targetId)

    if not targetSource then
        return false, err
    end

    local ped = GetPlayerPed(targetSource --[[@as string]])

    if ped == 0 then
        return false, locale('teleport_busy')
    end

    local coords = GetEntityCoords(ped)

    core:SetPlayerBucket(source, core:GetPlayerBucket(targetSource))
    SetEntityCoords(GetPlayerPed(source --[[@as string]]), coords.x, coords.y, coords.z + 1.0, false, false, false, false)

    Admin.log(source, 'teleported to', targetData)

    return true, locale('teleported_to_player')
end)

---@param targetId integer
---@return boolean success
---@return string message
lib.callback.register('admin:server:bringPlayer', function(source, targetId)
    local targetSource, targetData, err = Admin.gateAndResolve(source, 'bring', targetId)

    if not targetSource then
        return false, err
    end

    local ped = GetPlayerPed(targetSource --[[@as string]])

    if ped == 0 then
        return false, locale('teleport_busy')
    end

    local coords = GetEntityCoords(GetPlayerPed(source --[[@as string]]))

    core:SetPlayerBucket(targetSource, core:GetPlayerBucket(source))
    SetEntityCoords(ped, coords.x, coords.y, coords.z + 1.0, false, false, false, false)

    Admin.log(source, 'brought', targetData)

    TriggerClientEvent('admin:notify', targetSource, 'inform', locale('teleported'))

    return true, locale('teleported_player')
end)

-- ------------------------------------------------------------------ state ----

---@param targetId integer
---@return boolean success
---@return string message
lib.callback.register('admin:server:revivePlayer', function(source, targetId)
    local targetSource, targetData, err = Admin.gateAndResolve(source, 'revive', targetId)

    if not targetSource then
        return false, err
    end

    TriggerClientEvent('admin:client:revive', targetSource)

    Admin.log(source, 'revived', targetData)

    return true, ('Revived %s.'):format(targetData.username)
end)

---@param targetId integer
---@return boolean success
---@return string message
lib.callback.register('admin:server:healPlayer', function(source, targetId)
    local targetSource, targetData, err = Admin.gateAndResolve(source, 'heal', targetId)

    if not targetSource then
        return false, err
    end

    TriggerClientEvent('admin:client:heal', targetSource)

    Admin.log(source, 'healed', targetData)

    return true, ('Healed %s.'):format(targetData.username)
end)

---@type table<Source, true>
local frozen = {}

---@param targetId integer
---@return boolean success
---@return string message
lib.callback.register('admin:server:freezePlayer', function(source, targetId)
    local targetSource, targetData, err = Admin.gateAndResolve(source, 'freeze', targetId)

    if not targetSource then
        return false, err
    end

    local isFrozen = not frozen[targetSource]
    frozen[targetSource] = isFrozen or nil

    TriggerClientEvent('admin:client:freeze', targetSource, isFrozen)

    Admin.log(source, isFrozen and 'froze' or 'unfroze', targetData)

    return true, isFrozen and locale('player_frozen') or locale('player_unfrozen')
end)

---@param targetId integer
---@return boolean success
---@return string message
lib.callback.register('admin:server:killPlayer', function(source, targetId)
    local targetSource, targetData, err = Admin.gateAndResolve(source, 'kill', targetId)

    if not targetSource then
        return false, err
    end

    SetEntityHealth(GetPlayerPed(targetSource --[[@as string]]), 0)

    Admin.log(source, 'killed', targetData)

    return true, ('Killed %s.'):format(targetData.username)
end)

AddEventHandler('playerDropped', function()
    frozen[source --[[@as Source]]] = nil
end)

---@param source Source
---@return boolean
exports('IsFrozen', function(source)
    return frozen[source] == true
end)

-- ------------------------------------------------------------ punishment ----

---@param data { targetId: integer, userId: integer?, reason: string? }
---@return boolean success
---@return string? error
lib.callback.register('admin:server:kickPlayer', function(source, data)
    if type(data) ~= 'table' then
        return false, 'Invalid request.'
    end

    local targetSource, targetData, err = Admin.gateAndResolve(source, 'kick', data.targetId or data.userId)

    if not targetSource then
        return false, err
    end

    local reason = type(data.reason) == 'string' and data.reason ~= '' and data.reason or 'No reason given'
    local staff = Admin.getUsername(source)

    Admin.db.recordAction(targetData.userId, 'kick', reason, staff)
    Admin.log(source, 'kicked', targetData, reason)

    core:KickPlayer(targetSource, locale('kicked', reason, core:GetConfig().urls.discord))

    return true
end)

---@param data { targetId: integer, userId: integer?, reason: string? }
---@return boolean success
---@return string? error
lib.callback.register('admin:server:warnPlayer', function(source, data)
    if type(data) ~= 'table' then
        return false, 'Invalid request.'
    end

    local targetSource, targetData, err = Admin.gateAndResolve(source, 'warn', data.targetId or data.userId)

    if not targetSource then
        return false, err
    end

    local reason = type(data.reason) == 'string' and data.reason ~= '' and data.reason or 'No reason given'
    local staff = Admin.getUsername(source)

    Admin.db.recordAction(targetData.userId, 'warn', reason, staff)
    Admin.log(source, 'warned', targetData, reason)

    -- ui/client/uis/admin.lua renders the on-screen warning from this.
    TriggerClientEvent('admin:warnPlayer', targetSource, reason, staff)

    return true
end)
