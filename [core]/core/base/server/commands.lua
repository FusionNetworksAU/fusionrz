---Staff and developer commands.
---
---Every command is registered through ox_lib so the ace check and the
---argument parsing are the library's job, not each handler's. The ace names
---follow core.<command>, granted in server.cfg.

---@param source Source
---@param target integer | string
---@return CorePlayer?
local function resolveTarget(source, target)
    local asNumber = tonumber(target)

    if asNumber then
        return Core.getPlayer(asNumber --[[@as Source]]) or Core.getPlayerByUserId(math.floor(asNumber))
    end

    return nil
end

---@param source Source
---@param message string
local function reply(source, message)
    if source == 0 then
        return lib.print.info(message)
    end

    TriggerClientEvent('chat:addMessage', source, { args = { 'core', message } })
end

lib.addCommand('coins', {
    help = 'Grant or take coins from a player',
    params = {
        { name = 'target', type = 'number', help = 'server id or user id' },
        { name = 'amount', type = 'number', help = 'negative to take' },
        { name = 'reason', type = 'string', help = 'audit reason', optional = true },
    },
    restricted = 'group.admin',
}, function(source, args)
    local player = resolveTarget(source, args.target)

    if not player then
        return reply(source, 'No such player.')
    end

    local ok, balance = player:adjustCoins(math.floor(args.amount), args.reason or ('staff:%s'):format(source))

    reply(source, ok
        and ('%s now has %s coins.'):format(player.username, balance)
        or ('%s cannot go below zero (has %s).'):format(player.username, balance))
end)

lib.addCommand('giveitem', {
    help = 'Grant a catalogue item to a player',
    params = {
        { name = 'target', type = 'number', help = 'server id or user id' },
        { name = 'item', type = 'string', help = 'item id' },
    },
    restricted = 'group.admin',
}, function(source, args)
    local player = resolveTarget(source, args.target)

    if not player then
        return reply(source, 'No such player.')
    end

    local ok, err = Core.giveItem(player, args.item)

    reply(source, ok and ('Gave %s to %s.'):format(args.item, player.username) or err or 'Failed.')
end)

lib.addCommand('refreshitems', {
    help = 'Reload the item catalogue from the database',
    restricted = 'group.admin',
}, function(source)
    reply(source, Core.refreshItems() and 'Item catalogue reloaded.' or 'Reload failed, see console.')
end)

lib.addCommand('bucket', {
    help = 'Move a player into a routing bucket',
    params = {
        { name = 'target', type = 'number', help = 'server id' },
        { name = 'bucket', type = 'number', help = 'bucket id' },
    },
    restricted = 'group.admin',
}, function(source, args)
    local player = resolveTarget(source, args.target)

    if not player then
        return reply(source, 'No such player.')
    end

    Core.setPlayerBucket(player.source, math.floor(args.bucket))

    reply(source, ('Moved %s to bucket %s.'):format(player.username, args.bucket))
end)

lib.addCommand('whois', {
    help = 'Show what core knows about a player',
    params = {
        { name = 'target', type = 'number', help = 'server id or user id' },
    },
    restricted = 'group.mod',
}, function(source, args)
    local player = resolveTarget(source, args.target)

    if not player then
        return reply(source, 'No such player.')
    end

    reply(source, ('%s | user %s | src %s | coins %s | bucket %s | playtime %sh | %s'):format(
        player.username,
        player.userId,
        player.source,
        player.coins,
        Core.getPlayerBucket(player.source),
        math.floor(player:getPlaytime() / 3600),
        Core.getPlayerLocation(player.source) or 'unknown'
    ))
end)

lib.addCommand('coreban', {
    help = 'Ban a player',
    params = {
        { name = 'target', type = 'number', help = 'server id' },
        { name = 'hours', type = 'number', help = '0 for permanent' },
        { name = 'reason', type = 'string', help = 'shown to the player' },
    },
    restricted = 'group.admin',
}, function(source, args)
    local player = Core.getPlayer(math.floor(args.target) --[[@as Source]])

    if not player then
        return reply(source, 'No such player.')
    end

    local seconds = args.hours > 0 and math.floor(args.hours * 3600) or nil
    local staff = Core.getPlayer(source)

    exports.core:BanPlayer(player.source, args.reason, seconds, staff and staff.username or 'CONSOLE')

    reply(source, ('Banned %s.'):format(player.username))
end)

lib.addCommand('coretests', {
    help = 'Run the core test suites',
    params = {
        { name = 'filter', type = 'string', help = 'only suites matching this', optional = true },
    },
    restricted = 'group.admin',
}, function(source, args)
    if Core.env.getEnv() == 'production' then
        return reply(source, 'Tests are disabled in production.')
    end

    local results = Core.runTests(args.filter)

    reply(source, ('%s passed, %s failed, %s skipped.'):format(results.passed, results.failed, results.skipped))
end)
