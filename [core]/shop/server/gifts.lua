---Gifting.
---
---A gift is a purchase the buyer pays for and the recipient claims. It is
---deliberately two steps: the recipient may be offline, and granting an item
---to someone who is not there would mean writing into an inventory core has
---not loaded. So the row sits in `shop_gifts` until it is claimed, and the
---claim is the only thing that touches the inventory.

local core = exports.core

---@param row table
---@return table?
local function toGift(row)
    local item = Shop.getItem(row.itemId)

    if not item then
        return nil
    end

    return {
        giftId = row.id,
        senderUserId = row.senderId,
        senderUsername = row.senderUsername,
        message = row.message,
        createdAt = row.createdAt,
        item = Shop.toEntry(item),
    }
end

---@param userId integer
---@return table[]
local function fetchPending(userId)
    local rows = MySQL.query.await([[
        SELECT g.id AS id, g.sender_id AS senderId, g.item_id AS itemId,
               g.message AS message, UNIX_TIMESTAMP(g.created_at) AS createdAt,
               u.username AS senderUsername
        FROM shop_gifts g
        LEFT JOIN users u ON u.userId = g.sender_id
        WHERE g.recipient_id = ? AND g.claimed_at IS NULL
        ORDER BY g.created_at ASC
    ]], { userId }) or {}

    local gifts = {}

    for index = 1, #rows do
        local gift = toGift(rows[index])

        if gift then
            gifts[#gifts + 1] = gift
        end
    end

    return gifts
end

---@param source Source
function Shop.pushGifts(source)
    local userId = Shop.getUserId(source)

    if not userId then
        return
    end

    TriggerClientEvent('shop:client:setGifts', source, fetchPending(userId))
end

---@param itemId string
---@param targetUserId integer
---@param creatorCode string?
---@return boolean success
---@return string? error
lib.callback.register('shop:server:giftItem', function(source, itemId, targetUserId, creatorCode)
    local recipientId = math.floor(tonumber(targetUserId) or 0)
    local senderId = Shop.getUserId(source)

    if not senderId then
        return false, 'No player loaded.'
    end

    if recipientId <= 0 or recipientId == senderId then
        return false, 'Pick someone else to gift to.'
    end

    if not MySQL.scalar.await('SELECT 1 FROM users WHERE userId = ? LIMIT 1', { recipientId }) then
        return false, 'That player does not exist.'
    end

    local pending = MySQL.scalar.await(
        'SELECT COUNT(*) FROM shop_gifts WHERE recipient_id = ? AND claimed_at IS NULL',
        { recipientId }
    ) or 0

    if pending >= Shop.tuning.gifts.maxPending then
        return false, 'That player has too many unclaimed gifts.'
    end

    local ok, err = Shop.chargeAndRecord(source, itemId, creatorCode, recipientId)

    if not ok then
        return false, err
    end

    local giftId = MySQL.insert.await(
        'INSERT INTO shop_gifts (sender_id, recipient_id, item_id) VALUES (?, ?, ?)',
        { senderId, recipientId, itemId }
    )

    -- If the recipient happens to be online, their mailbox updates without
    -- them reopening the menu.
    for _, playerSource in ipairs(core:GetPlayerSources()) do
        if Shop.getUserId(playerSource) == recipientId then
            local gift = toGift({
                id = giftId,
                senderId = senderId,
                itemId = itemId,
                senderUsername = Shop.getPlayer(source).username,
                createdAt = os.time(),
            })

            if gift then
                TriggerClientEvent('shop:client:addGift', playerSource, gift)
            end

            break
        end
    end

    return true
end)

---@param giftId integer
---@return boolean success
---@return string? error
lib.callback.register('shop:server:claimGift', function(source, giftId)
    local userId = Shop.getUserId(source)
    local id = math.floor(tonumber(giftId) or 0)

    if not userId or id <= 0 then
        return false, 'Invalid gift.'
    end

    local row = MySQL.single.await(
        'SELECT item_id AS itemId FROM shop_gifts WHERE id = ? AND recipient_id = ? AND claimed_at IS NULL',
        { id, userId }
    )

    if not row then
        return false, 'That gift is not waiting for you.'
    end

    -- Marked claimed first and only granted if that UPDATE actually changed a
    -- row: two claims racing each other then have exactly one winner, and the
    -- loser grants nothing.
    local affected = MySQL.update.await(
        'UPDATE shop_gifts SET claimed_at = NOW() WHERE id = ? AND recipient_id = ? AND claimed_at IS NULL',
        { id, userId }
    )

    if affected ~= 1 then
        return false, 'That gift has already been claimed.'
    end

    local granted, err = core:GiveItem(source, row.itemId)

    if not granted then
        -- Handing the gift back is better than swallowing it: the row returns
        -- to unclaimed and the player can try again.
        MySQL.update.await('UPDATE shop_gifts SET claimed_at = NULL WHERE id = ?', { id })

        return false, err or 'Could not grant the item.'
    end

    Shop.log(('%s claimed gift %s (%s)'):format(userId, id, row.itemId))

    TriggerClientEvent('shop:client:removeGift', source, id)
    Shop.pushAll(source)

    return true
end)
