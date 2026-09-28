local utils = Core.utils

---@param source Source
---@param user UserRecord
---@param identifiers PlayerIdentifiers
---@param tokens string[]
---@return CorePlayer?
function Core.loadPlayer(source, user, identifiers, tokens)
    if Core.playersBySource[source] then
        return Core.playersBySource[source]
    end

    local duplicate = Core.getPlayerByUserId(user.userId)

    if duplicate and duplicate.source ~= source then
        duplicate:save(true)
        duplicate:kick(locale('duplicate_license', user.license))

        Core.unregisterPlayer(duplicate.source)
    end

    local player = Core.CorePlayer.new(source, user, identifiers, tokens)

    Core.registerPlayer(player)

    Core.db.recordIdentity(player.userId, identifiers, tokens)
    Core.assignLobbyBucket(player)
    Core.refreshInventory(player)

    player:syncState()

    player.dirty = true
    player:save()

    -- core:onPlayerLoaded is raised by the CLIENT, in main.lua's loadPlayer,
    -- once it actually holds the data. Firing it from here would reach the
    -- client before its requestPlayer callback had returned, so every
    -- listener would re-read an empty PlayerData and cache that.
    TriggerEvent('core:server:onPlayerLoaded', source, player.userId)

    Core.log('connections', ('%s (%s) loaded [src %s]'):format(player.username, player.userId, source))

    return player
end

---@param player CorePlayer
---@param reason string?
function Core.dropPlayer(player, reason)
    player:save(true)

    Core.releaseBucket(player)
    Core.unsubscribeAll(player.source)
    Core.unregisterPlayer(player.source)

    TriggerEvent('core:server:onPlayerDropped', player.source, player.userId, reason)

    Core.log('connections', ('%s (%s) dropped: %s'):format(player.username, player.userId, reason or 'unknown'))
end

---@param source Source
---@param username string
---@param country string?
---@return table? clientData
---@return string? error
---@return table? inventorySnapshot
lib.callback.register('core:server:createUser', function(source, username, country)
    if Core.playersBySource[source] then
        return nil, 'You already have an account loaded.'
    end

    local identifiers = utils.getIdentifiers(source)

    identifiers.license = Core.toPrefixedLicense(identifiers.license)

    if not identifiers.license then
        return nil, locale('license_not_found')
    end

    local valid, reason = Core.isUsernameShapeValid(username)

    if not valid then
        return nil, reason
    end

    if Core.containsProfanity(username) then
        return nil, locale('username_profanity')
    end

    if Core.db.getUserByLicense(identifiers.license) then
        return nil, locale('duplicate_license_db', identifiers.license)
    end

    if Core.db.isUsernameTaken(username) then
        return nil, locale('username_taken')
    end

    local ok, userId = pcall(Core.db.createUser, identifiers, username, Core.normaliseCountry(country))

    if not ok or not userId then
        lib.print.error(('[core] user creation failed for %s: %s'):format(identifiers.license, userId))

        return nil, locale('user_creation_failed')
    end

    local user = Core.db.getUserById(userId)

    if not user then
        return nil, locale('no_user_found')
    end

    local player = Core.loadPlayer(source, user, identifiers, utils.getTokens(source))

    if not player then
        return nil, locale('no_user_found')
    end

    Core.log('connections', ('%s (%s) registered from %s'):format(username, userId, country or 'unknown'))

    return player:getClientData(), nil, Core.buildInventorySnapshot(player)
end)
