---Ranked state, and everything the other server files share.
---
---server/*.lua is glob-loaded alphabetically (friends, main, matches,
---parties, queue), so `Ranked` is created by whichever file loads first and
---filled in by the rest. Every file in here starts the same way.
---
---What is persisted and what is not is a deliberate split. Friends, blocks,
---rating and timeouts are in ranked.sql because losing them would matter.
---Parties, queues and live matches are in memory only: they are meaningless
---across a restart, and rebuilding them from a table would mean reconciling
---rows against players who are no longer connected.

Ranked = Ranked or {}

Ranked.config = require 'config.shared'

local core = exports.core


---@alias RankedModeType 'solo' | 'duo' | 'trio' | 'squad' | 'wars'
---@alias RankedFormation string
---@alias RankedPresence 'online' | 'invisible' | 'dnd' | 'lfg'

---Everyone loaded, keyed by userId. The UI talks entirely in userIds -- it
---never sees a server id -- so this is the index everything else goes
---through.
---@type table<integer, Source>
Ranked.sourceByUserId = {}

---@type table<integer, RankedPresence>
Ranked.presence = {}

-- ------------------------------------------------------------- lookups -----

---@param userId integer?
---@return Source?
function Ranked.getSource(userId)
    local playerSource = userId and Ranked.sourceByUserId[userId] or nil

    -- A stale entry is possible between a drop and the handler running, so
    -- the source is confirmed against core rather than trusted.
    if playerSource and core:GetPlayerData(playerSource) then
        return playerSource
    end

    return nil
end

---@param source Source
---@return integer?
function Ranked.getUserId(source)
    local data = core:GetPlayerData(source)

    return data and data.userId or nil
end

---@param userId integer
---@return { userId: integer, username: string, avatar: string? }?
function Ranked.getIdentity(userId)
    local playerSource = Ranked.getSource(userId)

    if playerSource then
        local data = core:GetPlayerData(playerSource)

        if data then
            return { userId = data.userId, username = data.username, avatar = data.avatar }
        end
    end

    local row = MySQL.single.await('SELECT userId, username FROM users WHERE userId = ?', { userId })

    return row and { userId = row.userId, username = row.username } or nil
end

---@param userId integer
---@return boolean
function Ranked.isOnline(userId)
    return Ranked.getSource(userId) ~= nil
end

---Presence as other players see it. Someone invisible is reported offline,
---which is the whole point of the setting.
---@param userId integer
---@return RankedPresence | 'offline'
function Ranked.getPresence(userId)
    if not Ranked.isOnline(userId) then
        return 'offline'
    end

    local status = Ranked.presence[userId] or 'online'

    return status == 'invisible' and 'offline' or status
end

---@param userId integer
---@param event string
---@param ... any
function Ranked.emit(userId, event, ...)
    local playerSource = Ranked.getSource(userId)

    if playerSource then
        TriggerClientEvent(event, playerSource, ...)
    end
end

---The ui exports live on the client, so the server cannot call them. Each
---one is reached by asking the player's own client to make the call.
---@param userId integer
---@param exportName string
---@param ... any
function Ranked.push(userId, exportName, ...)
    Ranked.emit(userId, 'ranked:client:uiExport', exportName, ...)
end

---@param message string
function Ranked.log(message)
    core:Log('ranked', message)
end

-- ------------------------------------------------------------- presence ----

---@param status RankedPresence
---@return boolean
lib.callback.register('ranked:server:setPresenceStatus', function(source, status)
    local userId = Ranked.getUserId(source)

    if not userId then
        return false
    end

    if status ~= 'online' and status ~= 'invisible' and status ~= 'dnd' and status ~= 'lfg' then
        return false
    end

    Ranked.presence[userId] = status

    -- Friends see the change immediately; the LFG board only lists people who
    -- actually chose 'lfg', so it is rebuilt on every transition in or out.
    Ranked.broadcastPresence(userId)
    Ranked.refreshLookingForGroup()

    return true
end)

-- ------------------------------------------------------------ lifecycle ----

AddEventHandler('core:server:onPlayerLoaded', function(source)
    local userId = Ranked.getUserId(source)

    if not userId then
        return
    end

    Ranked.sourceByUserId[userId] = source
    Ranked.presence[userId] = Ranked.presence[userId] or 'online'

    Ranked.pushFriendsData(userId)
    Ranked.pushBlockedUsers(userId)
    Ranked.pushGameModes(userId)
    Ranked.pushPartyData(userId)
    Ranked.broadcastPresence(userId)
    Ranked.refreshLookingForGroup()

    -- Two things can be waiting for them from before they disconnected: a
    -- match still running, and rating changes they never saw.
    Ranked.offerReconnect(userId)
    Ranked.pushPendingEloAdjustments(userId)
end)

-- sourceByUserId is only filled by onPlayerLoaded above, so a `restart ranked`
-- with players already in left it empty. Every push is routed through it
-- (Ranked.emit), which meant nobody got party data, podium members or
-- anything else until they reconnected. Re-register whoever is loaded.
CreateThread(function()
    for _, playerId in ipairs(GetPlayers()) do
        local playerSource = tonumber(playerId) --[[@as Source]]
        local userId = Ranked.getUserId(playerSource)

        if userId then
            Ranked.sourceByUserId[userId] = playerSource
            Ranked.presence[userId] = Ranked.presence[userId] or 'online'
        end
    end
end)

AddEventHandler('core:server:onPlayerDropped', function(source, userId)
    userId = userId or Ranked.getUserId(source)

    if not userId then
        return
    end

    Ranked.sourceByUserId[userId] = nil

    Ranked.onPlayerDroppedFromParty(userId)
    Ranked.onPlayerDroppedFromQueue(userId)
    Ranked.onPlayerDroppedFromMatch(userId)

    Ranked.broadcastPresence(userId)
    Ranked.refreshLookingForGroup()
end)
