---Refunds.
---
---A refund costs a token, not nothing: tokens are the whole mechanism that
---stops the store being a fitting room. The window in config/shared.lua is
---the second limit -- an item bought months ago is kept, whatever the token
---balance says.

local core = exports.core

---core's snapshot is keyed by item id, but TakeItem wants the entry id of one
---specific copy and core exposes no lookup for it. The row is read straight
---out of `user_inventory` -- read only; core still performs the removal, so
---its cache stays the one source of truth.
---@param userId integer
---@param itemId string
---@return integer?
local function findInventoryEntry(userId, itemId)
    return MySQL.scalar.await(
        'SELECT id FROM user_inventory WHERE user_id = ? AND item_id = ? ORDER BY id ASC LIMIT 1',
        { userId, itemId }
    )
end

---@param source Source
---@return integer
local function getTokens(source)
    local tokens = Shop.get(source, Shop.keys.refundTokens, Shop.tuning.refunds.startingTokens)

    return math.max(0, math.floor(tonumber(tokens) or 0))
end

---Purchases still inside the refund window that have not been refunded or
---given away. A gift is the sender's purchase but the recipient's item, so
---`gifted_to IS NULL` keeps it out of both players' refund lists.
---@param source Source
---@return table[]
local function fetchRefundable(source)
    local userId = Shop.getUserId(source)

    if not userId then
        return {}
    end

    local rows = MySQL.query.await([[
        SELECT id, item_id AS itemId, price, UNIX_TIMESTAMP(created_at) AS createdAt
        FROM shop_purchases
        WHERE user_id = ?
          AND refunded_at IS NULL
          AND gifted_to IS NULL
          AND created_at >= DATE_SUB(NOW(), INTERVAL ? SECOND)
        ORDER BY created_at DESC
    ]], { userId, Shop.tuning.refunds.windowSeconds }) or {}

    local refundable = {}

    for index = 1, #rows do
        local row = rows[index]
        local item = Shop.getItem(row.itemId)

        if item and not Shop.tuning.refunds.blocked[item.category] and Shop.owns(source, row.itemId) then
            local entry = Shop.toEntry(item)

            entry.purchaseId = row.id
            entry.price = row.price
            entry.purchasedAt = row.createdAt

            refundable[#refundable + 1] = entry
        end
    end

    return refundable
end

---@return { items: table[], tokens: integer }
lib.callback.register('shop:server:getRefundableItems', function(source)
    return {
        items = fetchRefundable(source),
        tokens = getTokens(source),
    }
end)

---@param itemId string
---@return boolean success
---@return string? error
lib.callback.register('shop:server:refundItem', function(source, itemId)
    local userId = Shop.getUserId(source)

    if not userId or type(itemId) ~= 'string' then
        return false, 'Invalid request.'
    end

    local tokens = getTokens(source)

    if tokens < 1 then
        return false, 'You have no refund tokens left.'
    end

    local item = Shop.getItem(itemId)

    if not item then
        return false, 'That item no longer exists.'
    end

    if Shop.tuning.refunds.blocked[item.category] then
        return false, 'That kind of item cannot be refunded.'
    end

    local row = MySQL.single.await([[
        SELECT id, price FROM shop_purchases
        WHERE user_id = ? AND item_id = ?
          AND refunded_at IS NULL
          AND gifted_to IS NULL
          AND created_at >= DATE_SUB(NOW(), INTERVAL ? SECOND)
        ORDER BY created_at DESC
        LIMIT 1
    ]], { userId, itemId, Shop.tuning.refunds.windowSeconds })

    if not row then
        return false, 'That purchase is outside the refund window.'
    end

    -- The purchase is closed first, for the same reason a gift claim is: two
    -- refunds racing each other must not both pay out.
    local affected = MySQL.update.await(
        'UPDATE shop_purchases SET refunded_at = NOW() WHERE id = ? AND refunded_at IS NULL',
        { row.id }
    )

    if affected ~= 1 then
        return false, 'That purchase has already been refunded.'
    end

    local entryId = findInventoryEntry(userId, itemId)

    if entryId then
        core:TakeItem(source, entryId)
    end

    core:AddCoins(source, row.price, ('shop:refund:%s'):format(itemId))
    Shop.set(source, Shop.keys.refundTokens, tokens - 1)

    Shop.log(('%s refunded %s for %s (%s tokens left)'):format(userId, itemId, row.price, tokens - 1))

    Shop.pushAll(source)

    return true
end)

---@param source Source
---@param amount integer
exports('GrantRefundTokens', function(source, amount)
    local tokens = getTokens(source) + math.max(0, math.floor(amount or 0))

    Shop.set(source, Shop.keys.refundTokens, tokens)
    Shop.pushAll(source)

    return tokens
end)
