---Player reports and the message thread on each one.
---
---Two audiences share one table: the reporter sees only their own
---(admin:setMyReports / admin:addMyReport...), staff see all of them
---(admin:addAdminReport...). Staff callbacks gate on the ace; player
---callbacks check the report actually belongs to the caller, because a
---report id is just a number a client could make up.

local core = exports.core

---@param source Source
---@param reportId integer
---@return integer? ownerId
---@return boolean isOwner
local function resolveOwnership(source, reportId)
    local userId = Admin.getUserId(source)
    local ownerId = Admin.db.getReportOwner(reportId)

    return ownerId, ownerId ~= nil and ownerId == userId
end

---@param source Source
function Admin.pushMyReports(source)
    local userId = Admin.getUserId(source)

    if not userId then
        return
    end

    local reports = Admin.db.getReportsByUser(userId)

    for index = 1, #reports do
        reports[index].messages = Admin.db.getReportMessages(reports[index].id)
    end

    TriggerClientEvent('admin:setMyReports', source, reports)
end

AddEventHandler('core:server:onPlayerLoaded', function(source)
    Admin.pushMyReports(source)
end)

-- ----------------------------------------------------------- player side ----

---@param data { playerId?: string, reason: string, description: string }
---@return boolean success
---@return string? error
lib.callback.register('admin:server:submitReport', function(source, data)
    if type(data) ~= 'table' or type(data.reason) ~= 'string' then
        return false, 'Invalid report.'
    end

    local userId = Admin.getUserId(source)

    if not userId then
        return false, 'No player loaded.'
    end

    local description = type(data.description) == 'string' and data.description or ''

    if #description > Admin.maxReportLength then
        return false, ('Your report must be at most %s characters.'):format(Admin.maxReportLength)
    end

    if core:ContainsProfanity(description) then
        return false, 'Your report contains profanities.'
    end

    -- Without this one player can bury the queue. Only open reports count, so
    -- resolving theirs frees the slot again.
    if Admin.db.countOpenReports(userId) >= Admin.maxReportsPerPlayer then
        return false, ('You already have %s open reports.'):format(Admin.maxReportsPerPlayer)
    end

    local targetUserId = tonumber(data.playerId)
    local reportId = Admin.db.createReport(userId, data.reason, description, targetUserId and math.floor(targetUserId) or nil)

    if not reportId then
        return false, 'Could not file that report.'
    end

    local report = {
        id = reportId,
        reason = data.reason,
        description = description,
        status = 'Open',
        createdAt = os.time(),
        createdBy = {
            userId = userId,
            username = Admin.getUsername(source),
            avatar = Admin.getAvatar(source),
        },
        messages = {},
    }

    TriggerClientEvent('admin:addMyReport', source, report)
    Admin.broadcastToStaff('admin:addAdminReport', report)

    core:Log('protection', ('%s (%s) filed report #%s: %s'):format(report.createdBy.username, userId, reportId, data.reason))

    return true
end)

---@param data { reportId: number, text: string }
---@return boolean success
---@return string? error
lib.callback.register('admin:server:sendReportMessage', function(source, data)
    if type(data) ~= 'table' or type(data.text) ~= 'string' then
        return false, 'Invalid message.'
    end

    local reportId = tonumber(data.reportId)

    if not reportId then
        return false, 'Invalid report.'
    end

    reportId = math.floor(reportId)

    local ownerId, isOwner = resolveOwnership(source, reportId)

    if not ownerId then
        return false, 'That report does not exist.'
    end

    if not isOwner then
        return false, 'That is not your report.'
    end

    local text = data.text:gsub('^%s+', ''):gsub('%s+$', '')

    if text == '' or #text > Admin.maxMessageLength then
        return false, 'Invalid message.'
    end

    Admin.db.addReportMessage(reportId, ownerId, text, false)

    local message = {
        username = Admin.getUsername(source),
        avatar = Admin.getAvatar(source),
        timestamp = os.time(),
        text = text,
    }

    TriggerClientEvent('admin:addMyReportMessage', source, { reportId = reportId, message = message })
    Admin.broadcastToStaff('admin:addAdminReportMessage', { reportId = reportId, message = message })

    return true
end)

-- ------------------------------------------------------------ staff side ----

---@return table[]
lib.callback.register('admin:server:getAllAdminReports', function(source)
    if not Admin.isStaff(source) then
        return {}
    end

    return Admin.db.getAllReports()
end)

---@param reportId integer
---@return table[]
lib.callback.register('admin:server:fetchReportMessages', function(source, reportId)
    if not Admin.isStaff(source) then
        return {}
    end

    reportId = tonumber(reportId) --[[@as integer]]

    return reportId and Admin.db.getReportMessages(math.floor(reportId)) or {}
end)

---@param data { reportId: number, text: string }
---@return boolean success
lib.callback.register('admin:server:sendAdminReportMessage', function(source, data)
    if not Admin.isStaff(source) or type(data) ~= 'table' or type(data.text) ~= 'string' then
        return false
    end

    local reportId = tonumber(data.reportId)

    if not reportId then
        return false
    end

    reportId = math.floor(reportId)

    local ownerId = Admin.db.getReportOwner(reportId)

    if not ownerId then
        return false
    end

    local text = data.text:gsub('^%s+', ''):gsub('%s+$', '')

    if text == '' or #text > Admin.maxMessageLength then
        return false
    end

    Admin.db.addReportMessage(reportId, Admin.getUserId(source), text, true)

    local message = {
        username = Admin.getUsername(source),
        avatar = Admin.getAvatar(source),
        timestamp = os.time(),
        text = text,
        tag = Admin.getTag(source),
    }

    Admin.broadcastToStaff('admin:addAdminReportMessage', { reportId = reportId, message = message })

    local owner = core:GetPlayerByUserId(ownerId)

    if owner and owner.source then
        TriggerClientEvent('admin:addMyReportMessage', owner.source, { reportId = reportId, message = message })
    end

    return true
end)

---@param reportId integer
---@return boolean success
lib.callback.register('admin:server:markReportAsResolved', function(source, reportId)
    if not Admin.isStaff(source) then
        return false
    end

    reportId = tonumber(reportId) --[[@as integer]]

    if not reportId then
        return false
    end

    reportId = math.floor(reportId)

    local ownerId = Admin.db.getReportOwner(reportId)
    local resolvedBy = Admin.getUsername(source)

    if not Admin.db.resolveReport(reportId, resolvedBy, Admin.getUserId(source)) then
        return false
    end

    -- Same object shape the panel builds for its own optimistic update:
    -- { username, avatar, timestamp (seconds), tag? }. A bare name here
    -- passes the `resolvedBy ?` guard and then throws on .timestamp.
    local payload = {
        reportId = reportId,
        resolvedBy = {
            username = resolvedBy,
            avatar = Admin.getAvatar(source),
            timestamp = os.time(),
            tag = Admin.getTag(source),
        },
    }

    Admin.broadcastToStaff('admin:markAdminReportAsResolved', payload)

    if ownerId then
        local owner = core:GetPlayerByUserId(ownerId)

        if owner and owner.source then
            TriggerClientEvent('admin:markMyReportAsResolved', owner.source, payload)
        end
    end

    core:Log('protection', ('%s resolved report #%s'):format(resolvedBy, reportId))

    return true
end)
