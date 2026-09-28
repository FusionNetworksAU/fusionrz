local core = exports.core

---@param source Source
---@param message string
local function reply(source, message)
    if source == 0 then
        return lib.print.info(message)
    end

    TriggerClientEvent('admin:notify', source, 'inform', message)
end

---@param source Source
---@param userId number
---@return Source? targetSource
---@return table? targetData
local function target(source, userId)
    local targetSource, targetData = Admin.resolveTarget(userId)

    if not targetSource then
        reply(source, locale('spectate_failed'))

        return nil
    end

    return targetSource, targetData
end

lib.addCommand('kick', {
    help = 'Kick a player by user id',
    params = {
        { name = 'userId', type = 'number', help = 'target user id' },
        { name = 'reason', type = 'string', help = 'shown to the player', optional = true },
    },
    restricted = 'group.admin',
}, function(source, args)
    local targetSource, targetData = target(source, args.userId)

    if not targetSource then return end

    local reason = args.reason or 'No reason given'

    Admin.db.recordAction(targetData.userId, 'kick', reason, Admin.getUsername(source))
    Admin.log(source, 'kicked', targetData, reason)

    core:KickPlayer(targetSource, locale('kicked', reason, core:GetConfig().urls.discord))
end)

lib.addCommand('ban', {
    help = 'Ban a player by user id',
    params = {
        { name = 'userId', type = 'number', help = 'target user id' },
        { name = 'hours', type = 'number', help = '0 for permanent' },
        { name = 'reason', type = 'string', help = 'shown to the player' },
    },
    restricted = 'group.admin',
}, function(source, args)
    local targetSource, targetData = target(source, args.userId)

    if not targetSource then return end

    local seconds = args.hours > 0 and math.floor(args.hours * 3600) or nil

    Admin.log(source, 'banned', targetData, args.reason)

    core:BanPlayer(targetSource, args.reason, seconds, Admin.getUsername(source))

    reply(source, ('Banned %s.'):format(targetData.username))
end)

lib.addCommand('warn', {
    help = 'Warn a player by user id',
    params = {
        { name = 'userId', type = 'number', help = 'target user id' },
        { name = 'reason', type = 'string', help = 'shown to the player' },
    },
    restricted = 'group.admin',
}, function(source, args)
    local targetSource, targetData = target(source, args.userId)

    if not targetSource then return end

    local staff = Admin.getUsername(source)

    Admin.db.recordAction(targetData.userId, 'warn', args.reason, staff)
    Admin.log(source, 'warned', targetData, args.reason)

    TriggerClientEvent('admin:warnPlayer', targetSource, args.reason, staff)

    reply(source, ('Warned %s.'):format(targetData.username))
end)

lib.addCommand('revive', {
    help = 'Revive a player, or yourself with no argument',
    params = {
        { name = 'userId', type = 'number', help = 'target user id', optional = true },
    },
    restricted = 'group.admin',
}, function(source, args)
    if not args.userId then
        TriggerClientEvent('admin:client:revive', source)

        return
    end

    local targetSource, targetData = target(source, args.userId)

    if not targetSource then return end

    TriggerClientEvent('admin:client:revive', targetSource)

    Admin.log(source, 'revived', targetData)
end)

lib.addCommand('goto', {
    help = 'Teleport to a player',
    params = {
        { name = 'userId', type = 'number', help = 'target user id' },
    },
    restricted = 'group.admin',
}, function(source, args)
    local targetSource, targetData = target(source, args.userId)

    if not targetSource then return end

    local coords = GetEntityCoords(GetPlayerPed(targetSource --[[@as string]]))

    core:SetPlayerBucket(source, core:GetPlayerBucket(targetSource))
    SetEntityCoords(GetPlayerPed(source --[[@as string]]), coords.x, coords.y, coords.z + 1.0, false, false, false, false)

    Admin.log(source, 'teleported to', targetData)

    reply(source, locale('teleported_to_player'))
end)

lib.addCommand('bring', {
    help = 'Teleport a player to you',
    params = {
        { name = 'userId', type = 'number', help = 'target user id' },
    },
    restricted = 'group.admin',
}, function(source, args)
    local targetSource, targetData = target(source, args.userId)

    if not targetSource then return end

    local coords = GetEntityCoords(GetPlayerPed(source --[[@as string]]))

    core:SetPlayerBucket(targetSource, core:GetPlayerBucket(source))
    SetEntityCoords(GetPlayerPed(targetSource --[[@as string]]), coords.x, coords.y, coords.z + 1.0, false, false, false, false)

    Admin.log(source, 'brought', targetData)

    TriggerClientEvent('admin:notify', targetSource, 'inform', locale('teleported'))
    reply(source, locale('teleported_player'))
end)

lib.addCommand('staff', {
    help = 'Send a staff chat message',
    params = {
        { name = 'message', type = 'string', help = 'message' },
    },
    restricted = 'group.admin',
}, function(source, args)
    Admin.broadcastToStaff('admin:addStaffChatMessage', {
        message = args.message,
        username = Admin.getUsername(source),
        avatar = Admin.getAvatar(source),
        timestamp = os.time(),
        tag = Admin.getTag(source),
    })
end)

lib.addCommand('admins', {
    help = 'How many staff are online',
    restricted = 'group.admin',
}, function(source)
    reply(source, ('%s staff online.'):format(Admin.countOnlineStaff()))
end)
