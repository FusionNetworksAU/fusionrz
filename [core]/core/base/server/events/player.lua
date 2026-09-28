---Player-facing net events and callbacks that are not part of the connection
---handshake in base/server/main.lua.

Core.guardEvent('core:server:requestTeleport', {
    burst = 5,
    rate = 1,
    args = { 'string' },
}, function(player, locationKey)
    local locations = require 'data.locations'
    local location = locations[locationKey]

    if not location then
        return
    end

    if location.disableLobbyUsage and Core.getPlayerBucket(player.source) ~= Core.LOBBY_BUCKET then
        return
    end

    if Core.teleportPlayer(player.source, location.coords) then
        Core.setPlayerLocation(player.source, locationKey)

        if location.allowedWeapons then
            Core.setWeaponWhitelist(player.source, location.allowedWeapons)
        else
            Core.resetWeaponWhitelist(player.source)
        end
    end
end)

Core.guardEvent('core:server:requestSpawn', { burst = 3, rate = 0.5 }, function(player)
    Core.teleportPlayer(player.source, require('config.client').spawnLocation)
    Core.teleportToSpawn(player.source)
    Core.resetWeaponWhitelist(player.source)
end)

Core.guardEvent('core:server:setAvatar', {
    burst = 3,
    rate = 0.2,
    args = { 'string' },
}, function(player, avatar)
    -- Only the Discord CDN, and only as a URL: this string ends up in the
    -- src of an <img> on every other player's HUD.
    if #avatar > 256 or not avatar:match('^https://cdn%.discordapp%.com/') then
        return
    end

    player:setAvatar(avatar)
end)

lib.callback.register('core:server:setUsername', function(source, username)
    local player = Core.getPlayer(source)

    if not player then
        return false, locale('no_user_found')
    end

    return player:setUsername(username)
end)

lib.callback.register('core:server:getPlayerData', function(source)
    local player = Core.getPlayer(source)

    return player and player:getClientData() or nil
end)

lib.callback.register('core:server:getInventory', function(source)
    local player = Core.getPlayer(source)

    return player and Core.buildInventorySnapshot(player) or nil
end)

lib.callback.register('core:server:equipItem', function(source, entryId)
    local player = Core.getPlayer(source)

    if not player or type(entryId) ~= 'number' then
        return false, 'No player loaded.'
    end

    return Core.equipItem(player, math.floor(entryId))
end)

---Purchases are resolved entirely here: the client sends an item id and
---nothing else, because a client that could name its own price would.
lib.callback.register('core:server:purchaseItem', function(source, itemId)
    local player = Core.getPlayer(source)

    if not player or type(itemId) ~= 'string' then
        return false, 'No player loaded.'
    end

    local item = Core.getItem(itemId)

    if not item or not item.purchasable or not item.price then
        return false, 'That item is not for sale.'
    end

    if Core.ownsItem(player, itemId) then
        return false, 'You already own that.'
    end

    local charged = player:removeCoins(item.price, ('purchase:%s'):format(itemId))

    if not charged then
        return false, 'You cannot afford that.'
    end

    local granted, err = Core.giveItem(player, itemId)

    if not granted then
        -- Refund rather than leave them short: the charge already landed in
        -- the users row, so failing quietly here is a lost balance.
        player:addCoins(item.price, ('refund:%s'):format(itemId))

        return false, err
    end

    return true
end)
