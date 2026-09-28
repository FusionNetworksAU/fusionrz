---Developer commands.
---
---The storefront reads core's `items` catalogue and nothing else, so most of
---what goes wrong with it is a question about that catalogue rather than
---about shop: is the item there, is it purchasable, does this player own it,
---what does today's rotation actually contain. These answer those without a
---database client.
---
---All restricted to group.admin, and all off unless `shop:debug 1` is set
---(or the server is not running as env=production) -- same two doors hopouts
---uses for its own dev commands.

Shop = Shop or {}

local core = exports.core

---Two ways in, because flipping the global `env` convar to get these commands
---would also change how core logs. `shop:debug 1` turns on just this
---resource's dev commands.
---@return boolean
local function isDebugEnabled()
    if GetConvarInt('shop:debug', 0) == 1 then
        return true
    end

    return GetConvar('env', 'production') ~= 'production'
end

---@param source Source
---@param message string
local function reply(source, message)
    if source == 0 then
        return lib.print.info(message)
    end

    TriggerClientEvent('chat:addMessage', source, { args = { 'shop', message } })
end

---@param source Source
---@return boolean
local function guard(source)
    if not isDebugEnabled() then
        reply(source, 'Shop debug commands are off. Set `shop:debug 1` in server.cfg.')

        return false
    end

    return true
end

---Most of these take a player and default to the caller, since the common
---case is testing on yourself.
---@param source Source
---@param target number?
---@return Source?
local function resolveTarget(source, target)
    if not target then
        return source ~= 0 and source or nil
    end

    local asSource = math.floor(target)

    if core:GetPlayerData(asSource) then
        return asSource
    end

    -- Fall back to treating it as a userId, which is what the UI shows.
    for _, playerSource in ipairs(core:GetPlayerSources()) do
        local data = core:GetPlayerData(playerSource)

        if data and data.userId == asSource then
            return playerSource
        end
    end

    return nil
end

-- ------------------------------------------------------------- catalogue ---

lib.addCommand('shopitems', {
    help = 'List catalogue items, optionally filtered to one category',
    params = {
        { name = 'category', type = 'string', help = 'e.g. clothing, weapons', optional = true },
    },
    restricted = 'group.admin',
}, function(source, args)
    if not guard(source) then return end

    local items = core:GetAllItems() or {}
    local matching = {}

    for _, item in pairs(items) do
        if not args.category or item.category == args.category then
            matching[#matching + 1] = item
        end
    end

    if #matching == 0 then
        return reply(source, args.category
            and ('No items in category "%s". The catalogue may simply be empty.'):format(args.category)
            or 'The items catalogue is empty -- nothing has been inserted into `items` yet.')
    end

    table.sort(matching, function(a, b)
        return a.id < b.id
    end)

    reply(source, ('%s item(s):'):format(#matching))

    -- Chunked, because one line per item floods the chat box on a real
    -- catalogue and the console truncates a single enormous line.
    for index = 1, math.min(#matching, 40) do
        local item = matching[index]

        reply(source, ('  %s [%s] %s%s'):format(
            item.id,
            item.category,
            item.price and ('%s coins'):format(item.price) or 'no price',
            item.purchasable and '' or ' (not purchasable)'
        ))
    end

    if #matching > 40 then
        reply(source, ('  ... and %s more'):format(#matching - 40))
    end
end)

lib.addCommand('shopitem', {
    help = 'Show one catalogue item in full',
    params = {
        { name = 'item', type = 'string', help = 'item id' },
    },
    restricted = 'group.admin',
}, function(source, args)
    if not guard(source) then return end

    local item = core:GetItem(args.item)

    if not item then
        return reply(source, ('No item "%s" in the catalogue.'):format(args.item))
    end

    reply(source, ('%s (%s) -- %s'):format(item.id, item.category, item.label))
    reply(source, ('  enabled=%s purchasable=%s price=%s rarity=%s'):format(
        tostring(item.enabled), tostring(item.purchasable), tostring(item.price), tostring(item.rarity)
    ))
    reply(source, ('  preview: %s'):format(json.encode(item.data or {})))
end)

lib.addCommand('shopreload', {
    help = 'Re-read the items catalogue from the database',
    restricted = 'group.admin',
}, function(source)
    if not guard(source) then return end

    core:RefreshItems()

    reply(source, 'Catalogue reloaded.')

    -- Everyone's store is built from the catalogue, so a reload that changed
    -- it leaves every open menu stale until it is pushed again.
    for _, playerSource in ipairs(core:GetPlayerSources()) do
        Shop.pushStore(playerSource)
        Shop.pushAll(playerSource)
    end
end)

-- ------------------------------------------------------------- inventory ---

lib.addCommand('shopgive', {
    help = 'Grant a catalogue item without charging for it',
    params = {
        { name = 'item', type = 'string', help = 'item id' },
        { name = 'target', type = 'number', help = 'server id or user id', optional = true },
    },
    restricted = 'group.admin',
}, function(source, args)
    if not guard(source) then return end

    local target = resolveTarget(source, args.target)

    if not target then
        return reply(source, 'No such player.')
    end

    local ok, err = core:GiveItem(target, args.item)

    if not ok then
        return reply(source, ('Could not grant %s: %s'):format(args.item, err or 'unknown'))
    end

    Shop.pushAll(target)

    reply(source, ('Granted %s to %s.'):format(args.item, Shop.getPlayer(target).username))
end)

lib.addCommand('shopowned', {
    help = "List what a player owns",
    params = {
        { name = 'target', type = 'number', help = 'server id or user id', optional = true },
    },
    restricted = 'group.admin',
}, function(source, args)
    if not guard(source) then return end

    local target = resolveTarget(source, args.target)

    if not target then
        return reply(source, 'No such player.')
    end

    local owned = Shop.getOwnedItems(target)

    if #owned == 0 then
        return reply(source, ('%s owns nothing.'):format(Shop.getPlayer(target).username))
    end

    reply(source, ('%s owns %s item(s):'):format(Shop.getPlayer(target).username, #owned))

    for index = 1, math.min(#owned, 40) do
        reply(source, ('  %s [%s]'):format(owned[index].id, owned[index].category))
    end

    if #owned > 40 then
        reply(source, ('  ... and %s more'):format(#owned - 40))
    end
end)

lib.addCommand('shopequipped', {
    help = 'Show which cosmetics a player has equipped',
    params = {
        { name = 'target', type = 'number', help = 'server id or user id', optional = true },
    },
    restricted = 'group.admin',
}, function(source, args)
    if not guard(source) then return end

    local target = resolveTarget(source, args.target)

    if not target then
        return reply(source, 'No such player.')
    end

    for name, key in pairs(Shop.keys) do
        local value = Shop.get(target, key, nil)

        if value ~= nil then
            reply(source, ('  %s (%s) = %s'):format(
                name, key, type(value) == 'table' and json.encode(value) or tostring(value)
            ))
        end
    end
end)

-- ----------------------------------------------------------------- store ---

lib.addCommand('shopstore', {
    help = "Reroll and re-push a player's daily store",
    params = {
        { name = 'target', type = 'number', help = 'server id or user id', optional = true },
    },
    restricted = 'group.admin',
}, function(source, args)
    if not guard(source) then return end

    local target = resolveTarget(source, args.target)

    if not target then
        return reply(source, 'No such player.')
    end

    -- A new seed against today's day key, the same thing the paid refresh
    -- does -- minus the charge.
    Shop.set(target, Shop.keys.dailySeed, math.random(1, 2147483646))
    Shop.pushStore(target)

    reply(source, ('Rerolled the store for %s.'):format(Shop.getPlayer(target).username))
end)

lib.addCommand('shoptokens', {
    help = 'Grant refund tokens',
    params = {
        { name = 'amount', type = 'number', help = 'how many' },
        { name = 'target', type = 'number', help = 'server id or user id', optional = true },
    },
    restricted = 'group.admin',
}, function(source, args)
    if not guard(source) then return end

    local target = resolveTarget(source, args.target)

    if not target then
        return reply(source, 'No such player.')
    end

    local tokens = exports.shop:GrantRefundTokens(target, args.amount)

    reply(source, ('%s now has %s refund token(s).'):format(Shop.getPlayer(target).username, tokens))
end)

-- --------------------------------------------------------- creator codes ---

lib.addCommand('shopcode', {
    help = 'Create or update a creator code',
    params = {
        { name = 'code', type = 'string', help = 'the code itself' },
        { name = 'target', type = 'number', help = 'server id or user id of the owner', optional = true },
        { name = 'share', type = 'number', help = 'fraction of each sale, e.g. 0.1', optional = true },
    },
    restricted = 'group.admin',
}, function(source, args)
    if not guard(source) then return end

    local target = resolveTarget(source, args.target)

    if not target then
        return reply(source, 'No such player.')
    end

    local userId = Shop.getUserId(target)
    local share = math.min(1.0, math.max(0.0, args.share or Shop.tuning.creators.defaultShare))

    MySQL.query.await([[
        INSERT INTO shop_creator_codes (code, user_id, share) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE user_id = VALUES(user_id), share = VALUES(share), enabled = 1
    ]], { args.code, userId, share })

    Shop.pushCreatorSelfInfo(target)

    reply(source, ('Code "%s" now belongs to %s at %s%%.'):format(
        args.code, Shop.getPlayer(target).username, math.floor(share * 100)
    ))
end)

lib.addCommand('shopschema', {
    help = "Check that shop's own tables exist",
    restricted = 'group.admin',
}, function(source)
    if not guard(source) then return end

    local tables = { 'shop_purchases', 'shop_gifts', 'shop_creator_codes' }
    local missing = {}

    for index = 1, #tables do
        local exists = MySQL.scalar.await([[
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = DATABASE() AND table_name = ?
        ]], { tables[index] })

        if not exists then
            missing[#missing + 1] = tables[index]
        end
    end

    if #missing == 0 then
        return reply(source, 'All shop tables are present.')
    end

    reply(source, ('Missing: %s -- import shop/shop.sql.'):format(table.concat(missing, ', ')))
end)
