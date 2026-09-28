---Friends, requests, blocks and the looking-for-group board.
---
---Friendship is symmetric and stored once, with the lower userId first, so
---"are these two friends" is one primary-key lookup. Requests and blocks are
---directional and stored as sent.

Ranked = Ranked or {}

---@param a integer
---@param b integer
---@return integer lower
---@return integer higher
local function orderPair(a, b)
    if a < b then
        return a, b
    end

    return b, a
end

---@param userId integer
---@param otherId integer
---@return boolean
function Ranked.areFriends(userId, otherId)
    local low, high = orderPair(userId, otherId)

    return MySQL.scalar.await(
        'SELECT 1 FROM ranked_friends WHERE user_a = ? AND user_b = ? LIMIT 1',
        { low, high }
    ) ~= nil
end

---Directional: has `userId` blocked `otherId`.
---@param userId integer
---@param otherId integer
---@return boolean
function Ranked.hasBlocked(userId, otherId)
    return MySQL.scalar.await(
        'SELECT 1 FROM ranked_blocks WHERE user_id = ? AND blocked_id = ? LIMIT 1',
        { userId, otherId }
    ) ~= nil
end

---Either direction. Nothing social should happen between two players when
---one of them has blocked the other, regardless of who is acting.
---@param userId integer
---@param otherId integer
---@return boolean
function Ranked.eitherBlocked(userId, otherId)
    return MySQL.scalar.await([[
        SELECT 1 FROM ranked_blocks
        WHERE (user_id = ? AND blocked_id = ?) OR (user_id = ? AND blocked_id = ?)
        LIMIT 1
    ]], { userId, otherId, otherId, userId }) ~= nil
end

---@param userId integer
---@return integer[]
function Ranked.getFriendIds(userId)
    local rows = MySQL.query.await([[
        SELECT CASE WHEN user_a = ? THEN user_b ELSE user_a END AS friendId
        FROM ranked_friends
        WHERE user_a = ? OR user_b = ?
    ]], { userId, userId, userId }) or {}

    local ids = {}

    for index = 1, #rows do
        ids[index] = rows[index].friendId
    end

    return ids
end

---The shape the friends drawer renders.
---@param friendId integer
---@return table?
local function toFriendData(friendId)
    local identity = Ranked.getIdentity(friendId)

    if not identity then
        return nil
    end

    local status = Ranked.getPresence(friendId)

    -- `isOnline` is the field the NUI reads (and defaults to false when it
    -- is missing); it was only ever sent as `online`, so every friend showed
    -- offline no matter what. `online` stays for anything else reading it.
    return {
        userId = identity.userId,
        username = identity.username,
        avatar = identity.avatar,
        status = status,
        isOnline = status ~= 'offline',
        online = status ~= 'offline',
        elo = Ranked.getElo(friendId, 'solo'),
    }
end

---@param userId integer
---@return table[]
local function buildFriends(userId)
    local ids = Ranked.getFriendIds(userId)
    local friends = {}

    for index = 1, #ids do
        local data = toFriendData(ids[index])

        if data then
            friends[#friends + 1] = data
        end
    end

    -- Online first, then alphabetical: the drawer is a list you scan for
    -- someone to play with, not a directory.
    table.sort(friends, function(a, b)
        if a.online ~= b.online then
            return a.online
        end

        return a.username < b.username
    end)

    return friends
end

---@param userId integer
---@param column string 'sender_id' or 'recipient_id'
---@param otherColumn string
---@return table[]
local function buildRequests(userId, column, otherColumn)
    local rows = MySQL.query.await(([[
        SELECT %s AS otherId FROM ranked_friend_requests WHERE %s = ?
    ]]):format(otherColumn, column), { userId }) or {}

    local requests = {}

    for index = 1, #rows do
        local identity = Ranked.getIdentity(rows[index].otherId)

        if identity then
            requests[#requests + 1] = {
                userId = identity.userId,
                username = identity.username,
                avatar = identity.avatar,
            }
        end
    end

    return requests
end

---@param userId integer
function Ranked.pushFriendsData(userId)
    Ranked.push(userId, 'setFriends', buildFriends(userId))
    Ranked.push(userId, 'setIncomingFriendRequests', buildRequests(userId, 'recipient_id', 'sender_id'))
    Ranked.push(userId, 'setOutgoingFriendRequests', buildRequests(userId, 'sender_id', 'recipient_id'))
    Ranked.push(userId, 'setRecentlyPlayed', Ranked.buildRecentlyPlayed(userId))
    Ranked.push(userId, 'setRankedPresenceStatus', Ranked.presence[userId] or 'online')
end

---@param userId integer
---@return table[]
function Ranked.buildRecentlyPlayed(userId)
    local rows = MySQL.query.await([[
        SELECT other_id AS otherId FROM ranked_recent_players
        WHERE user_id = ?
        ORDER BY played_at DESC
        LIMIT 20
    ]], { userId }) or {}

    local players = {}

    for index = 1, #rows do
        local data = toFriendData(rows[index].otherId)

        if data then
            players[#players + 1] = data
        end
    end

    return players
end

---@param userId integer
function Ranked.pushBlockedUsers(userId)
    local rows = MySQL.query.await(
        'SELECT blocked_id AS blockedId FROM ranked_blocks WHERE user_id = ?',
        { userId }
    ) or {}

    local blocked = {}

    for index = 1, #rows do
        local identity = Ranked.getIdentity(rows[index].blockedId)

        if identity then
            blocked[#blocked + 1] = {
                userId = identity.userId,
                username = identity.username,
                avatar = identity.avatar,
            }
        end
    end

    Ranked.push(userId, 'setBlockedUsers', blocked)
end

---Tells everyone who has this player as a friend that their status moved.
---@param userId integer
function Ranked.broadcastPresence(userId)
    local ids = Ranked.getFriendIds(userId)
    local status = Ranked.getPresence(userId)

    for index = 1, #ids do
        Ranked.push(ids[index], 'updateFriendsPresence', {
            { userId = userId, status = status, isOnline = status ~= 'offline', online = status ~= 'offline' },
        })
    end
end

---The LFG board is everyone currently advertising, minus anyone the viewer
---has blocked in either direction.
function Ranked.refreshLookingForGroup()
    local advertising = {}

    for userId, status in pairs(Ranked.presence) do
        if status == 'lfg' and Ranked.isOnline(userId) then
            local identity = Ranked.getIdentity(userId)

            if identity then
                advertising[#advertising + 1] = {
                    userId = identity.userId,
                    username = identity.username,
                    avatar = identity.avatar,
                    elo = Ranked.getElo(userId, 'solo'),
                    isOnline = true,
                }
            end
        end
    end

    for viewerId in pairs(Ranked.sourceByUserId) do
        local visible = {}

        for index = 1, #advertising do
            local entry = advertising[index]

            if entry.userId ~= viewerId and not Ranked.eitherBlocked(viewerId, entry.userId) then
                visible[#visible + 1] = entry
            end
        end

        Ranked.push(viewerId, 'setLookingForGroupPlayers', visible)
    end
end

-- ------------------------------------------------------------- requests ----

---@param data { userId: integer?, username: string? }
---@return 'sent' | 'accepted' | false
---@return string? error
lib.callback.register('ranked:server:sendFriendRequest', function(source, data)
    local userId = Ranked.getUserId(source)

    if not userId or type(data) ~= 'table' then
        return false, 'Invalid request.'
    end

    -- The drawer can send either a picked user or a typed name.
    local targetId = tonumber(data.userId)

    if not targetId and type(data.username) == 'string' then
        targetId = MySQL.scalar.await('SELECT userId FROM users WHERE username = ? LIMIT 1', { data.username })
    end

    if not targetId then
        return false, 'No such player.'
    end

    targetId = math.floor(targetId)

    if targetId == userId then
        return false, 'You cannot add yourself.'
    end

    if Ranked.eitherBlocked(userId, targetId) then
        return false, 'You cannot add that player.'
    end

    if Ranked.areFriends(userId, targetId) then
        return false, 'You are already friends.'
    end

    -- A request back the other way turns this into an accept, which is what
    -- people expect when two players add each other at the same time.
    local incoming = MySQL.scalar.await(
        'SELECT 1 FROM ranked_friend_requests WHERE sender_id = ? AND recipient_id = ? LIMIT 1',
        { targetId, userId }
    )

    if incoming then
        Ranked.acceptFriendRequest(userId, targetId)

        return 'accepted'
    end

    MySQL.insert.await(
        'INSERT IGNORE INTO ranked_friend_requests (sender_id, recipient_id) VALUES (?, ?)',
        { userId, targetId }
    )

    local sender = Ranked.getIdentity(userId)

    Ranked.push(targetId, 'addIncomingFriendRequest', {
        userId = sender.userId,
        username = sender.username,
        avatar = sender.avatar,
    })

    local recipient = Ranked.getIdentity(targetId)

    Ranked.push(userId, 'addOutgoingFriendRequest', {
        userId = recipient.userId,
        username = recipient.username,
        avatar = recipient.avatar,
    })

    return 'sent'
end)

---@param userId integer the accepting player
---@param senderId integer
function Ranked.acceptFriendRequest(userId, senderId)
    local low, high = orderPair(userId, senderId)

    MySQL.query.await(
        'DELETE FROM ranked_friend_requests WHERE (sender_id = ? AND recipient_id = ?) OR (sender_id = ? AND recipient_id = ?)',
        { senderId, userId, userId, senderId }
    )

    MySQL.insert.await(
        'INSERT IGNORE INTO ranked_friends (user_a, user_b) VALUES (?, ?)',
        { low, high }
    )

    Ranked.push(userId, 'removeIncomingFriendRequest', senderId)
    Ranked.push(senderId, 'removeOutgoingFriendRequest', userId)

    Ranked.push(userId, 'setInboundFriendAccepted', senderId)
    Ranked.push(senderId, 'setOutboundFriendAccepted', userId)

    Ranked.pushFriendsData(userId)
    Ranked.pushFriendsData(senderId)
end

---@param senderId integer
---@return table? friend
---@return string? error
lib.callback.register('ranked:server:acceptFriendRequest', function(source, senderId)
    local userId = Ranked.getUserId(source)
    local targetId = math.floor(tonumber(senderId) or 0)

    if not userId or targetId <= 0 then
        return nil, 'Invalid request.'
    end

    local exists = MySQL.scalar.await(
        'SELECT 1 FROM ranked_friend_requests WHERE sender_id = ? AND recipient_id = ? LIMIT 1',
        { targetId, userId }
    )

    if not exists then
        return nil, 'That request is no longer there.'
    end

    Ranked.acceptFriendRequest(userId, targetId)

    return toFriendData(targetId)
end)

---@param senderId integer
---@return boolean success
---@return string? error
lib.callback.register('ranked:server:denyFriendRequest', function(source, senderId)
    local userId = Ranked.getUserId(source)
    local targetId = math.floor(tonumber(senderId) or 0)

    if not userId or targetId <= 0 then
        return false, 'Invalid request.'
    end

    MySQL.query.await(
        'DELETE FROM ranked_friend_requests WHERE sender_id = ? AND recipient_id = ?',
        { targetId, userId }
    )

    Ranked.push(userId, 'removeIncomingFriendRequest', targetId)
    Ranked.push(targetId, 'removeOutgoingFriendRequest', userId)

    return true
end)

---@param recipientId integer
---@return boolean success
---@return string? error
lib.callback.register('ranked:server:revokeFriendRequest', function(source, recipientId)
    local userId = Ranked.getUserId(source)
    local targetId = math.floor(tonumber(recipientId) or 0)

    if not userId or targetId <= 0 then
        return false, 'Invalid request.'
    end

    MySQL.query.await(
        'DELETE FROM ranked_friend_requests WHERE sender_id = ? AND recipient_id = ?',
        { userId, targetId }
    )

    Ranked.push(userId, 'removeOutgoingFriendRequest', targetId)
    Ranked.push(targetId, 'removeIncomingFriendRequest', userId)

    return true
end)

---@param friendId integer
---@return boolean success
---@return string? error
lib.callback.register('ranked:server:removeFriend', function(source, friendId)
    local userId = Ranked.getUserId(source)
    local targetId = math.floor(tonumber(friendId) or 0)

    if not userId or targetId <= 0 then
        return false, 'Invalid request.'
    end

    local low, high = orderPair(userId, targetId)

    MySQL.query.await('DELETE FROM ranked_friends WHERE user_a = ? AND user_b = ?', { low, high })

    Ranked.push(userId, 'removeFriend', targetId)
    Ranked.push(targetId, 'removeFriend', userId)

    Ranked.pushFriendsData(userId)
    Ranked.pushFriendsData(targetId)

    return true
end)

-- --------------------------------------------------------------- blocks ----

---Blocking also tears down whatever relationship exists: the friendship, any
---pending request either way, and their party membership if they are sitting
---in one together. Otherwise a block leaves them still attached.
---@param blockedId integer
---@return table? blocked
---@return string? error
lib.callback.register('ranked:server:blockUser', function(source, blockedId)
    local userId = Ranked.getUserId(source)
    local targetId = math.floor(tonumber(blockedId) or 0)

    if not userId or targetId <= 0 then
        return nil, 'Invalid request.'
    end

    if targetId == userId then
        return nil, 'You cannot block yourself.'
    end

    local identity = Ranked.getIdentity(targetId)

    if not identity then
        return nil, 'No such player.'
    end

    MySQL.insert.await(
        'INSERT IGNORE INTO ranked_blocks (user_id, blocked_id) VALUES (?, ?)',
        { userId, targetId }
    )

    local low, high = orderPair(userId, targetId)

    MySQL.query.await('DELETE FROM ranked_friends WHERE user_a = ? AND user_b = ?', { low, high })
    MySQL.query.await(
        'DELETE FROM ranked_friend_requests WHERE (sender_id = ? AND recipient_id = ?) OR (sender_id = ? AND recipient_id = ?)',
        { userId, targetId, targetId, userId }
    )

    Ranked.separateFromParty(userId, targetId)

    Ranked.push(targetId, 'blockedByUser', userId)

    Ranked.pushFriendsData(userId)
    Ranked.pushFriendsData(targetId)
    Ranked.pushBlockedUsers(userId)
    Ranked.refreshLookingForGroup()

    return {
        userId = identity.userId,
        username = identity.username,
        avatar = identity.avatar,
    }
end)

---@param blockedId integer
---@return boolean success
---@return string? error
lib.callback.register('ranked:server:unblockUser', function(source, blockedId)
    local userId = Ranked.getUserId(source)
    local targetId = math.floor(tonumber(blockedId) or 0)

    if not userId or targetId <= 0 then
        return false, 'Invalid request.'
    end

    MySQL.query.await(
        'DELETE FROM ranked_blocks WHERE user_id = ? AND blocked_id = ?',
        { userId, targetId }
    )

    Ranked.pushBlockedUsers(userId)
    Ranked.refreshLookingForGroup()

    return true
end)

---Records that a set of players were in a match together, for the recently
---played list. Called by matches.lua when a match settles.
---@param userIds integer[]
function Ranked.recordRecentlyPlayed(userIds)
    for i = 1, #userIds do
        for j = 1, #userIds do
            if i ~= j then
                MySQL.query.await([[
                    INSERT INTO ranked_recent_players (user_id, other_id) VALUES (?, ?)
                    ON DUPLICATE KEY UPDATE played_at = NOW()
                ]], { userIds[i], userIds[j] })
            end
        end
    end
end
