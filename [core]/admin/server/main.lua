---THE query layer and the online roster.
---
---All SQL in this resource lives here, the same arrangement core uses, so
---pointing it at a different schema means editing one file. Bans are the
---exception by design: core owns `user_bans` and this reads it rather than
---keeping a second copy that could disagree.
---
---Everything keys on users.userId, which is the id the admin UI hands back
---for every row it lists.

local core = exports.core

---The admin NUI mixes units: reports and their messages carry UNIX seconds,
---but accountCreatedAt and every history timestamp are milliseconds (its
---own browser fixtures use Date.now() for those and Date.now()/1e3 for the
---others). It also formats them unguarded, so a nil -- which Lua omits from
---the JSON entirely, arriving as undefined -- throws
---"RangeError: Invalid time value" and takes the whole panel down. Hence a
---number, always.
---@param seconds integer?
---@return integer milliseconds
local function toMillis(seconds)
    return math.floor((tonumber(seconds) or 0) * 1000)
end

Admin.toMillis = toMillis

Admin.db = {}

-- ------------------------------------------------------------ queries ----

---@param userId integer
---@return { username: string?, discord: string?, accountCreatedAt: integer?, playtimeSeconds: integer }
function Admin.db.getProfile(userId)
    local row = MySQL.single.await([[
        SELECT u.username, u.discord,
               UNIX_TIMESTAMP(p.created_at) AS created_at,
               p.playtime
        FROM users u
        LEFT JOIN user_profiles p ON p.user_id = u.userId
        WHERE u.userId = ?
    ]], { userId })

    if not row then
        return { playtimeSeconds = 0 }
    end

    return {
        username = row.username,
        discord = row.discord,
        accountCreatedAt = row.created_at,
        playtimeSeconds = row.playtime or 0,
    }
end

---@param userId integer
---@return { timestamp: integer, adminUsername: string, reason: string, expiresAt: integer? }[]
function Admin.db.getBanHistory(userId)
    local rows = MySQL.query.await([[
        SELECT id, UNIX_TIMESTAMP(created_at) AS created_at, staff, reason, UNIX_TIMESTAMP(expires_at) AS expires_at
        FROM user_bans
        WHERE user_id = ?
        ORDER BY created_at DESC
    ]], { userId })

    local history = {}

    for index = 1, #(rows or {}) do
        local row = rows[index]

        history[index] = {
            id = row.id,
            timestamp = toMillis(row.created_at),
            adminUsername = row.staff or 'SYSTEM',
            reason = row.reason,
            expiresAt = row.expires_at,
        }
    end

    return history
end

---@param userId integer
---@param kind 'kick' | 'warn'
---@return { timestamp: integer, adminUsername: string, reason: string }[]
function Admin.db.getActionHistory(userId, kind)
    local rows = MySQL.query.await([[
        SELECT UNIX_TIMESTAMP(created_at) AS created_at, staff, reason
        FROM admin_actions
        WHERE user_id = ? AND kind = ?
        ORDER BY created_at DESC
    ]], { userId, kind })

    local history = {}

    for index = 1, #(rows or {}) do
        local row = rows[index]

        history[index] = {
            timestamp = toMillis(row.created_at),
            adminUsername = row.staff or 'SYSTEM',
            reason = row.reason,
        }
    end

    return history
end

---@param userId integer
---@param kind 'kick' | 'warn'
---@param reason string
---@param staff string
---@return integer? id
function Admin.db.recordAction(userId, kind, reason, staff)
    return MySQL.insert.await(
        'INSERT INTO admin_actions (user_id, kind, reason, staff, created_at) VALUES (?, ?, ?, ?, NOW())',
        { userId, kind, reason, staff }
    )
end

---@param row table
---@return table
local function hydrateReport(row)
    return {
        id = row.id,
        reason = row.reason,
        description = row.description,
        status = row.resolved_at and 'Resolved' or 'Open',
        createdAt = row.created_at,
        -- An OBJECT, not a name: the panel renders
        -- resolvedBy.avatar/.username/.timestamp and guards only on
        -- resolvedBy itself, so a bare string passes the guard and then
        -- throws on the undefined timestamp. `tag` is optional and guarded
        -- separately, so it is left out.
        resolvedBy = row.resolved_at and {
            username = row.resolved_by or 'Unknown',
            avatar = row.resolver_avatar,
            timestamp = row.resolved_at_unix or 0,
        } or nil,
        createdBy = {
            userId = row.user_id,
            username = row.username,
            avatar = row.avatar,
        },
        messages = {},
    }
end

local REPORT_SELECT = [[
    SELECT r.id, r.user_id, r.reason, r.description, r.resolved_by,
           UNIX_TIMESTAMP(r.created_at) AS created_at,
           r.resolved_at, UNIX_TIMESTAMP(r.resolved_at) AS resolved_at_unix,
           u.username, p.avatar,
           rp.avatar AS resolver_avatar
    FROM admin_reports r
    LEFT JOIN users u ON u.userId = r.user_id
    LEFT JOIN user_profiles p ON p.user_id = r.user_id
    LEFT JOIN user_profiles rp ON rp.user_id = r.resolved_by_user_id
]]

---@return table[]
function Admin.db.getAllReports()
    local rows = MySQL.query.await(REPORT_SELECT .. ' ORDER BY r.created_at DESC LIMIT 200')
    local reports = {}

    for index = 1, #(rows or {}) do
        reports[index] = hydrateReport(rows[index])
    end

    return reports
end

---@param userId integer
---@return table[]
function Admin.db.getReportsByUser(userId)
    local rows = MySQL.query.await(REPORT_SELECT .. ' WHERE r.user_id = ? ORDER BY r.created_at DESC', { userId })
    local reports = {}

    for index = 1, #(rows or {}) do
        reports[index] = hydrateReport(rows[index])
    end

    return reports
end

---@param userId integer
---@return integer
function Admin.db.countOpenReports(userId)
    local row = MySQL.single.await(
        'SELECT COUNT(*) AS total FROM admin_reports WHERE user_id = ? AND resolved_at IS NULL',
        { userId }
    )

    return row and row.total or 0
end

---@param userId integer
---@param reason string
---@param description string
---@param targetUserId integer?
---@return integer? reportId
function Admin.db.createReport(userId, reason, description, targetUserId)
    return MySQL.insert.await(
        'INSERT INTO admin_reports (user_id, target_user_id, reason, description, created_at) VALUES (?, ?, ?, ?, NOW())',
        { userId, targetUserId, reason, description }
    )
end

---@param reportId integer
---@param resolvedBy string
---@param resolvedByUserId integer?
---@return boolean
function Admin.db.resolveReport(reportId, resolvedBy, resolvedByUserId)
    local affected = MySQL.update.await(
        'UPDATE admin_reports SET resolved_at = NOW(), resolved_by = ?, resolved_by_user_id = ? WHERE id = ? AND resolved_at IS NULL',
        { resolvedBy, resolvedByUserId, reportId }
    )

    return (affected or 0) > 0
end

---@param reportId integer
---@return integer? userId
function Admin.db.getReportOwner(reportId)
    local row = MySQL.single.await('SELECT user_id FROM admin_reports WHERE id = ?', { reportId })

    return row and row.user_id
end

---@param reportId integer
---@return { username: string, avatar: string?, timestamp: integer, text: string }[]
function Admin.db.getReportMessages(reportId)
    local rows = MySQL.query.await([[
        SELECT m.text, UNIX_TIMESTAMP(m.created_at) AS created_at, u.username, p.avatar
        FROM admin_report_messages m
        LEFT JOIN users u ON u.userId = m.user_id
        LEFT JOIN user_profiles p ON p.user_id = m.user_id
        WHERE m.report_id = ?
        ORDER BY m.created_at ASC
    ]], { reportId })

    local messages = {}

    for index = 1, #(rows or {}) do
        local row = rows[index]

        messages[index] = {
            username = row.username or 'Unknown',
            avatar = row.avatar,
            timestamp = row.created_at,
            text = row.text,
        }
    end

    return messages
end

---@param reportId integer
---@param userId integer?
---@param text string
---@param isStaff boolean
---@return integer? id
function Admin.db.addReportMessage(reportId, userId, text, isStaff)
    return MySQL.insert.await(
        'INSERT INTO admin_report_messages (report_id, user_id, text, is_staff, created_at) VALUES (?, ?, ?, ?, NOW())',
        { reportId, userId, text, isStaff and 1 or 0 }
    )
end

-- ------------------------------------------------------------- roster ----

---@type table[]
local disconnected = {}

---Menus currently open, per player, per menu id ('admin' or 'reports'). Two
---open at once must not have the first one closed cancel the other, so this
---is a set per source rather than a boolean.
---@type table<Source, table<string, true>>
local watchers = {}

---@param source Source
---@return table
function Admin.buildPlayerEntry(source)
    return {
        source = source,
        userId = Admin.getUserId(source),
        username = Admin.getUsername(source),
        avatar = Admin.getAvatar(source),
        role = Admin.getRoleLabel(source),
        activity = core:GetPlayerLocation(source) or 'LOBBY',
    }
end

---@return table[]
function Admin.getConnected()
    local list = {}

    for _, playerSource in ipairs(core:GetPlayerSources()) do
        list[#list + 1] = Admin.buildPlayerEntry(playerSource)
    end

    return list
end

---@return table[]
function Admin.getDisconnected()
    return disconnected
end

---@param userId integer
---@return table?
function Admin.findDisconnected(userId)
    for index = 1, #disconnected do
        if disconnected[index].userId == userId then
            return disconnected[index]
        end
    end

    return nil
end

---userId ONLY, never a server id. Every row the admin NUI lists carries both,
---and falling back to source would silently target the wrong player whenever
---a userId happened to equal someone's server id -- on a small server those
---collide immediately. A miss fails loudly instead.
---@param targetId integer | string
---@return Source? source
---@return table? playerData
function Admin.resolveTarget(targetId)
    local userId = tonumber(targetId)

    if not userId then
        return nil
    end

    local player = core:GetPlayerByUserId(math.floor(userId))

    if player and player.source then
        return player.source, player
    end

    return nil
end

---@param source Source
---@param action string
---@param targetId integer
---@return Source? targetSource
---@return table? targetData
---@return string? error
function Admin.gateAndResolve(source, action, targetId)
    local allowed, err = Admin.gate(source, action)

    if not allowed then
        return nil, nil, err
    end

    local targetSource, targetData = Admin.resolveTarget(targetId)

    if not targetSource then
        return nil, nil, locale('spectate_failed')
    end

    return targetSource, targetData
end

---@param source Source
---@param action string
---@param targetData table?
---@param detail string?
function Admin.log(source, action, targetData, detail)
    core:Log('commands', ('%s (src %s) %s %s%s'):format(
        Admin.getUsername(source),
        source,
        action,
        targetData and ('%s (%s)'):format(targetData.username, targetData.userId) or 'unknown',
        detail and (': ' .. detail) or ''
    ))
end

---@param eventName string
---@param ... any
function Admin.broadcastToStaff(eventName, ...)
    for _, playerSource in ipairs(core:GetPlayerSources()) do
        if Admin.isStaff(playerSource) then
            TriggerClientEvent(eventName, playerSource, ...)
        end
    end
end

---@return integer
function Admin.countOnlineStaff()
    local count = 0

    for _, playerSource in ipairs(core:GetPlayerSources()) do
        if Admin.isStaff(playerSource) then
            count += 1
        end
    end

    return count
end

local function broadcastActiveAdmins()
    local count = Admin.countOnlineStaff()

    for watcherSource in pairs(watchers) do
        TriggerClientEvent('admin:setActiveAdmins', watcherSource, count)
    end
end

Admin.broadcastActiveAdmins = broadcastActiveAdmins

---ui/client/uis/admin.lua and reports.lua both subscribe with their own id
---and expect the current count straight back as the return.
---@param menuId string
---@return integer
lib.callback.register('admin:server:subscribeActiveAdmins', function(source, menuId)
    if menuId == 'admin' and not Admin.isStaff(source) then
        return 0
    end

    local open = watchers[source]

    if not open then
        open = {}
        watchers[source] = open
    end

    open[type(menuId) == 'string' and menuId or 'admin'] = true

    return Admin.countOnlineStaff()
end)

RegisterNetEvent('admin:server:unsubscribeActiveAdmins', function(menuId)
    local source = source --[[@as Source]]
    local open = watchers[source]

    if not open then
        return
    end

    open[type(menuId) == 'string' and menuId or 'admin'] = nil

    if not next(open) then
        watchers[source] = nil
    end
end)

AddEventHandler('core:server:onPlayerLoaded', function(source)
    local entry = Admin.buildPlayerEntry(source)

    -- A rejoin should not leave the old row sitting in the DISCONNECTED tab.
    for index = #disconnected, 1, -1 do
        if disconnected[index].userId == entry.userId then
            table.remove(disconnected, index)
        end
    end

    Admin.broadcastToStaff('admin:playerJoined', entry)
    Admin.broadcastToStaff('admin:removeDisconnected', { entry.userId })

    broadcastActiveAdmins()
end)

AddEventHandler('core:server:onPlayerDropped', function(source, userId, reason)
    table.insert(disconnected, 1, {
        source = source,
        userId = userId,
        username = Admin.getUsername(source),
        avatar = Admin.getAvatar(source),
        role = Admin.getRoleLabel(source),
        timestamp = os.time(),
        reason = reason or 'Unknown',
    })

    while #disconnected > Admin.disconnectedHistory do
        table.remove(disconnected)
    end

    watchers[source] = nil

    Admin.broadcastToStaff('admin:playerDropped', userId, disconnected[1])

    broadcastActiveAdmins()
end)

---The client has no way to read an ace, so it asks before opening the menu.
---This is convenience only -- every callback still checks for itself, because
---a client that lies about this would simply get refused later.
---@return boolean
lib.callback.register('admin:server:canOpenMenu', function(source)
    return Admin.isStaff(source)
end)
