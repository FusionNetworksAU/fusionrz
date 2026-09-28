---Bans.
---
---core owns the `user_bans` table and the connection-time banlist check, so
---this file is the staff-facing half only: issuing a ban, lifting one, and
---reading the history for the player info panel. Going through core keeps
---one definition of what "banned" means instead of two that can drift.

local core = exports.core

---@param banId integer | string
---@param expiresAt integer?
---@param reason string
---@return string
local function buildMessage(banId, expiresAt, reason)
    return locale('banned', banId, Admin.formatExpiry(expiresAt), reason, core:GetConfig().urls.discord)
end

Admin.buildBanMessage = buildMessage

---@param data { targetId: integer, userId: integer?, reason: string?, hours: number?, duration: number? }
---@return boolean success
---@return string? error
lib.callback.register('admin:server:banPlayer', function(source, data)
    if type(data) ~= 'table' then
        return false, 'Invalid request.'
    end

    local targetSource, targetData, err = Admin.gateAndResolve(source, 'ban', data.targetId or data.userId)

    if not targetSource then
        return false, err
    end

    local reason = type(data.reason) == 'string' and data.reason ~= '' and data.reason or 'No reason given'
    local hours = tonumber(data.hours) or tonumber(data.duration)
    local seconds = (hours and hours > 0) and math.floor(hours * 3600) or nil
    local staff = Admin.getUsername(source)

    Admin.log(source, 'banned', targetData, ('%s (%s)'):format(reason, seconds and (hours .. 'h') or 'permanent'))

    -- core writes user_bans and drops the player with its own formatted
    -- message, so the ban history panel picks this up for free.
    local banId = core:BanPlayer(targetSource, reason, seconds, staff)

    if not banId then
        return false, 'Could not record the ban.'
    end

    return true
end)

---@param userId integer
---@return { timestamp: integer, adminUsername: string, reason: string, expiresAt: integer? }[]
lib.callback.register('admin:server:getBanHistory', function(source, userId)
    if not Admin.isStaff(source) then
        return {}
    end

    userId = tonumber(userId) --[[@as integer]]

    return userId and Admin.db.getBanHistory(math.floor(userId)) or {}
end)

---@param banId integer
---@return boolean success
---@return string? error
lib.callback.register('admin:server:liftBan', function(source, banId)
    local allowed, err = Admin.gate(source, 'ban')

    if not allowed then
        return false, err
    end

    banId = tonumber(banId) --[[@as integer]]

    if not banId then
        return false, 'Invalid ban.'
    end

    -- Expiring rather than deleting: the history panel should still show that
    -- the ban happened, and who lifted it.
    local affected = MySQL.update.await(
        'UPDATE user_bans SET expires_at = NOW() WHERE id = ? AND (expires_at IS NULL OR expires_at > NOW())',
        { math.floor(banId) }
    )

    if (affected or 0) == 0 then
        return false, 'That ban is not active.'
    end

    core:Log('bans', ('%s lifted ban #%s'):format(Admin.getUsername(source), banId))

    return true
end)
