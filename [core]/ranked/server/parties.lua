---Parties.
---
---Everyone is in a party, always -- a player on their own is a party of one
---with themselves as leader. That removes the "create a party" step and every
---"are you in a party yet" branch: inviting someone means merging their party
---into yours, and leaving means splitting back out into a party of one.
---
---In memory only. A party across a restart would be a party of people who are
---no longer connected.

Ranked = Ranked or {}

---@class RankedParty
---@field id integer
---@field leaderId integer
---@field members integer[] userIds, leader first
---@field mode RankedModeType
---@field formation RankedFormation?
---@field queuedAt integer? os.time when the party entered the queue

---@type table<integer, RankedParty>
local parties = {}

---@type table<integer, integer> userId -> party id
local partyByUser = {}

---@type table<integer, { fromId: integer, expiresAt: integer }> invited userId -> invite
local invites = {}

---@type table<integer, { fromId: integer, partyId: integer }> leader userId -> pending join request
local joinRequests = {}

local nextPartyId = 0

---Party size per mode. `wars` is open-ended, so it is capped at the largest
---thing the lobby can render rather than by a rule.
local MODE_SIZES = {
    solo = 1,
    duo = 2,
    trio = 3,
    squad = 4,
    wars = 10,
}

---@param mode string?
---@return boolean
local function isValidMode(mode)
    return mode ~= nil and MODE_SIZES[mode] ~= nil
end

---@param userId integer
---@return RankedParty
function Ranked.getParty(userId)
    local partyId = partyByUser[userId]
    local party = partyId and parties[partyId] or nil

    if party then
        return party
    end

    nextPartyId += 1

    party = {
        id = nextPartyId,
        leaderId = userId,
        members = { userId },
        mode = 'solo',
        formation = nil,
        queuedAt = nil,
    }

    parties[party.id] = party
    partyByUser[userId] = party.id

    return party
end

---@param userId integer
---@return boolean
local function isLeader(userId)
    local party = Ranked.getParty(userId)

    return party.leaderId == userId
end

---@param party RankedParty
---@param userId integer
---@return integer?
local function indexOf(party, userId)
    for index = 1, #party.members do
        if party.members[index] == userId then
            return index
        end
    end

    return nil
end

---@param party RankedParty
---@return table
local function buildPartyData(party)
    local users = {}

    for index = 1, #party.members do
        local memberId = party.members[index]
        local identity = Ranked.getIdentity(memberId)

        if identity then
            users[#users + 1] = {
                userId = identity.userId,
                username = identity.username,
                avatar = identity.avatar,
                rank = Ranked.getRankName(memberId, party.mode),
                ping = Ranked.getPing(memberId),
                banner = Ranked.getBanner(memberId),
                winStreak = Ranked.getWinStreak(memberId, party.mode),
                level = Ranked.getLevel(memberId),
                prestige = Ranked.getPrestige(memberId),
                gangTag = Ranked.getGangTag(memberId),
            }
        else
            users[#users + 1] = {
                userId = memberId,
                username = ('Player %d'):format(memberId),
            }
        end
    end

    return {
        game = {
            formation = party.formation or party.mode,
            mode = party.mode,
            inQueue = party.queuedAt ~= nil,
            currentTime = party.queuedAt and (os.time() - party.queuedAt) or 0,
            estimatedTime = Ranked.getEstimatedQueueSeconds(party.mode),
        },
        leader = party.leaderId,
        users = users,
    }
end

---The podium dresses each ped as its player, so it needs the saved
---appearance (core's user_appearance) alongside the name card data. Kept off
---the NUI payload: the menu has no use for it and it is the bulk of the size.
---@param users table[]
---@return table[]
local function buildPodiumMembers(users)
    local members = {}

    for index = 1, #users do
        local user = users[index]
        local playerSource = Ranked.getSource(user.userId)
        local appearance = nil

        if playerSource then
            local ok, result = pcall(function()
                return exports.core:GetAppearance(playerSource)
            end)

            appearance = ok and type(result) == 'table' and result or nil
        end

        members[index] = {
            userId = user.userId,
            appearance = appearance,
        }
    end

    return members
end

---@param party RankedParty
function Ranked.pushParty(party)
    local data = buildPartyData(party)
    local podiumMembers = buildPodiumMembers(data.users)

    for index = 1, #party.members do
        local memberId = party.members[index]

        Ranked.push(memberId, 'setRankedPartyData', data)
        -- Slot count = the mode's team size: a solo lobby shows just you, a
        -- duo you plus one invite slot, and so on -- not always five.
        Ranked.emit(memberId, 'ranked:client:setPodiumMembers', podiumMembers, Ranked.getModeSize(party.mode))
    end
end

---@param userId integer
function Ranked.pushPartyData(userId)
    Ranked.pushParty(Ranked.getParty(userId))
end

---@param userId integer
---@param party RankedParty
local function detach(userId, party)
    local index = indexOf(party, userId)

    if index then
        table.remove(party.members, index)
    end

    partyByUser[userId] = nil

    if #party.members == 0 then
        parties[party.id] = nil

        return
    end

    if party.leaderId == userId then
        party.leaderId = party.members[1]
    end

    Ranked.dequeueParty(party, 'party changed')
    Ranked.pushParty(party)
end

---@param userId integer
---@param isLeaveParty boolean? true leaves, false/nil disbands if leader
RegisterNetEvent('ranked:server:leaveParty', function(isLeaveParty)
    local source = source --[[@as Source]]
    local userId = Ranked.getUserId(source)

    if not userId then
        return
    end

    local party = Ranked.getParty(userId)

    if #party.members <= 1 then
        return
    end

    if isLeaveParty == false and party.leaderId == userId then
        local members = { table.unpack(party.members) }

        Ranked.dequeueParty(party, 'party disbanded')

        for index = 1, #members do
            partyByUser[members[index]] = nil
        end

        parties[party.id] = nil

        for index = 1, #members do
            Ranked.pushPartyData(members[index])
        end

        return
    end

    detach(userId, party)
    Ranked.pushPartyData(userId)
end)

---@param userId integer
RegisterNetEvent('ranked:server:kickPartyPlayer', function(targetUserId)
    local source = source --[[@as Source]]
    local userId = Ranked.getUserId(source)
    local targetId = math.floor(tonumber(targetUserId) or 0)

    if not userId or targetId <= 0 or targetId == userId or not isLeader(userId) then
        return
    end

    local party = Ranked.getParty(userId)

    if not indexOf(party, targetId) then
        return
    end

    detach(targetId, party)
    Ranked.pushPartyData(targetId)

    Ranked.log(('%s kicked %s from party %s'):format(userId, targetId, party.id))
end)

---@param targetUserId integer
RegisterNetEvent('ranked:server:promotePartyPlayer', function(targetUserId)
    local source = source --[[@as Source]]
    local userId = Ranked.getUserId(source)
    local targetId = math.floor(tonumber(targetUserId) or 0)

    if not userId or targetId <= 0 or not isLeader(userId) then
        return
    end

    local party = Ranked.getParty(userId)

    if not indexOf(party, targetId) then
        return
    end

    party.leaderId = targetId

    Ranked.pushParty(party)
end)

---@param mode RankedModeType
---@return boolean
lib.callback.register('ranked:server:setPartyMode', function(source, mode)
    local userId = Ranked.getUserId(source)

    if not userId or not isValidMode(mode) or not isLeader(userId) then
        return false
    end

    local party = Ranked.getParty(userId)

    if #party.members > MODE_SIZES[mode] then
        return false
    end

    party.mode = mode

    Ranked.dequeueParty(party, 'mode changed')
    Ranked.pushParty(party)

    return true
end)

---@param formation RankedFormation
---@return boolean
lib.callback.register('ranked:server:setPartyFormation', function(source, formation)
    local userId = Ranked.getUserId(source)

    if not userId or type(formation) ~= 'string' or not isLeader(userId) then
        return false
    end

    local party = Ranked.getParty(userId)

    party.formation = formation

    Ranked.pushParty(party)

    return true
end)

---@param targetUserId integer
---@return boolean success
---@return string? error
lib.callback.register('ranked:server:sendPartyInvite', function(source, targetUserId)
    local userId = Ranked.getUserId(source)
    local targetId = math.floor(tonumber(targetUserId) or 0)

    if not userId or targetId <= 0 or targetId == userId then
        return false, 'Invalid request.'
    end

    if not Ranked.isOnline(targetId) then
        return false, 'That player is offline.'
    end

    if Ranked.eitherBlocked(userId, targetId) then
        return false, 'You cannot invite that player.'
    end

    local party = Ranked.getParty(userId)

    if not isLeader(userId) then
        return false, 'Only the party leader can invite.'
    end

    if #party.members >= (MODE_SIZES[party.mode] or 1) then
        return false, 'Your party is full.'
    end

    if indexOf(party, targetId) then
        return false, 'They are already in your party.'
    end

    if Ranked.presence[targetId] == 'dnd' then
        return false, 'That player is not accepting invites.'
    end

    invites[targetId] = {
        fromId = userId,
        expiresAt = GetGameTimer() + Ranked.config.partyInviteTimeMsec,
    }

    local sender = Ranked.getIdentity(userId)

    Ranked.push(targetId, 'setPartyInvite', {
        userId = sender.userId,
        username = sender.username,
        avatar = sender.avatar,
        seconds = math.floor(Ranked.config.partyInviteTimeMsec / 1000),
    })

    Ranked.push(userId, 'setFriendInviteStatus', { userId = targetId, status = 'invited' })

    SetTimeout(Ranked.config.partyInviteTimeMsec, function()
        local invite = invites[targetId]

        if invite and invite.fromId == userId then
            invites[targetId] = nil

            Ranked.push(targetId, 'setPartyInvite', nil)
            Ranked.push(userId, 'setFriendInviteStatus', { userId = targetId, status = 'expired' })
        end
    end)

    return true
end)

RegisterNetEvent('ranked:server:acceptPartyInvite', function()
    local source = source --[[@as Source]]
    local userId = Ranked.getUserId(source)

    if not userId then
        return
    end

    local invite = invites[userId]

    invites[userId] = nil
    Ranked.push(userId, 'setPartyInvite', nil)

    if not invite then
        return
    end

    local party = Ranked.getParty(invite.fromId)

    if #party.members >= (MODE_SIZES[party.mode] or 1) then
        return Ranked.push(userId, 'setFriendInviteStatus', { userId = invite.fromId, status = 'full' })
    end

    Ranked.joinParty(userId, party)
end)

RegisterNetEvent('ranked:server:rejectPartyInvite', function()
    local source = source --[[@as Source]]
    local userId = Ranked.getUserId(source)

    if not userId then
        return
    end

    local invite = invites[userId]

    invites[userId] = nil
    Ranked.push(userId, 'setPartyInvite', nil)

    if invite then
        Ranked.push(invite.fromId, 'setFriendInviteStatus', { userId = userId, status = 'rejected' })
    end
end)

---@param userId integer
---@param party RankedParty
function Ranked.joinParty(userId, party)
    local current = Ranked.getParty(userId)

    if current.id == party.id then
        return
    end

    detach(userId, current)

    party.members[#party.members + 1] = userId
    partyByUser[userId] = party.id

    Ranked.dequeueParty(party, 'party changed')
    Ranked.pushParty(party)
end

---@param targetUserId integer the leader being asked
---@return boolean success
---@return string? error
lib.callback.register('ranked:server:requestPartyJoin', function(source, targetUserId)
    local userId = Ranked.getUserId(source)
    local targetId = math.floor(tonumber(targetUserId) or 0)

    if not userId or targetId <= 0 or targetId == userId then
        return false, 'Invalid request.'
    end

    if not Ranked.isOnline(targetId) then
        return false, 'That player is offline.'
    end

    if Ranked.eitherBlocked(userId, targetId) then
        return false, 'You cannot join that player.'
    end

    local party = Ranked.getParty(targetId)

    if #party.members >= (MODE_SIZES[party.mode] or 1) then
        return false, 'That party is full.'
    end

    joinRequests[party.leaderId] = { fromId = userId, partyId = party.id }

    local requester = Ranked.getIdentity(userId)

    Ranked.push(party.leaderId, 'setPartyInvite', {
        userId = requester.userId,
        username = requester.username,
        avatar = requester.avatar,
        isJoinRequest = true,
        seconds = math.floor(Ranked.config.partyInviteTimeMsec / 1000),
    })

    return true
end)

RegisterNetEvent('ranked:server:acceptPartyJoinRequest', function()
    local source = source --[[@as Source]]
    local userId = Ranked.getUserId(source)

    if not userId then
        return
    end

    local request = joinRequests[userId]

    joinRequests[userId] = nil
    Ranked.push(userId, 'setPartyInvite', nil)

    if not request then
        return
    end

    local party = parties[request.partyId]

    if not party or #party.members >= (MODE_SIZES[party.mode] or 1) then
        return
    end

    Ranked.joinParty(request.fromId, party)
end)

RegisterNetEvent('ranked:server:rejectPartyJoinRequest', function()
    local source = source --[[@as Source]]
    local userId = Ranked.getUserId(source)

    if not userId then
        return
    end

    local request = joinRequests[userId]

    joinRequests[userId] = nil
    Ranked.push(userId, 'setPartyInvite', nil)

    if request then
        Ranked.push(request.fromId, 'setFriendInviteStatus', { userId = userId, status = 'rejected' })
    end
end)

---@param userId integer
---@param blockedId integer
function Ranked.separateFromParty(userId, blockedId)
    local party = Ranked.getParty(userId)

    if indexOf(party, blockedId) then
        detach(blockedId, party)
        Ranked.pushPartyData(blockedId)
    end

    invites[blockedId] = nil
    invites[userId] = nil
end

---@param userId integer
function Ranked.onPlayerDroppedFromParty(userId)
    local partyId = partyByUser[userId]

    invites[userId] = nil
    joinRequests[userId] = nil

    if not partyId then
        return
    end

    local party = parties[partyId]

    if party then
        detach(userId, party)
    end
end

---@param userId integer
---@return RankedParty?
function Ranked.getPartyIfExists(userId)
    local partyId = partyByUser[userId]

    return partyId and parties[partyId] or nil
end

---@return table<integer, RankedParty>
function Ranked.getAllParties()
    return parties
end

---@param mode string
---@return integer
function Ranked.getModeSize(mode)
    return MODE_SIZES[mode] or 1
end

RegisterNetEvent('ranked:server:returnToSpawn', function()
    local source = source --[[@as Source]]

    if not Ranked.getUserId(source) then
        return
    end

    exports.core:TeleportToSpawn(source)
end)

RegisterNetEvent('ranked:server:refreshUi', function()
    local userId = Ranked.getUserId(source)

    if not userId then
        return
    end

    -- The client is asking, so it is certainly here: make sure the pushes
    -- below can find it even if its registration was lost to a restart.
    Ranked.sourceByUserId[userId] = source

    Ranked.pushPartyData(userId)
    Ranked.pushFriendsData(userId)
    Ranked.pushGameModes(userId)
end)

-- A saved character shows on the lobby podium straight away, for the player
-- and everyone in their party, instead of on the next party change.
AddEventHandler('appearance:server:onSaved', function(source)
    local player = exports.core:GetPlayerData(source)
    local userId = player and player.userId

    if userId and Ranked.getPartyIfExists(userId) then
        Ranked.pushPartyData(userId)
    end
end)
