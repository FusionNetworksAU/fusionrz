---In-game text chat.
---
---The server owns every routing decision. The NUI picks a mode id and sends
---text; it never decides who hears it, and the scope it echoes back is
---re-derived here before a single recipient is resolved. A client that lies
---about its modeId, its scopeId or its own name therefore gains nothing.
---
---Modes are described once in MODES below. Each one answers three questions:
---can this player use it, what scope are they in right now, and who receives
---a message sent into that scope. Everything else in this file -- commands,
---exports, suggestions -- is built on those three answers.

local core = exports.core

-- ------------------------------------------------------------------ config --

local MAX_MESSAGE_LENGTH = 240

---Proximity for `local_chat`, in game units.
local LOCAL_RADIUS = 30.0

---Token bucket per player. A burst of four lets someone fire off a short
---exchange without being throttled; the sustained rate is the one that
---decides how much they can say over a minute.
local MESSAGE_BURST = 4
local MESSAGE_RATE = 0.5

---Mirrors admin/shared/main.lua. Duplicated rather than required because
---admin owns its own Lua state and exposes no role lookup, and chat has to
---keep working when the admin resource is not running.
---@type { ace: string, label: string, colour: string }[]
local ROLES = {
    { ace = 'group.owner',   label = 'Owner',     colour = '#e0c216' },
    { ace = 'group.admin',   label = 'Admin',     colour = '#cc1653' },
    { ace = 'group.mod',     label = 'Moderator', colour = '#34e5eb' },
    { ace = 'group.support', label = 'Support',   colour = '#49D27E' },
}

local STAFF_ACE = 'group.admin'

-- ------------------------------------------------------------------ state ---

---Scopes registered by gamemode resources through the SetPlayerScope export.
---A scope is what makes `team` and `game` mean something: without one the
---mode is simply not offered to that player.
---@type table<Source, table<string, string>> source -> modeId -> scopeId
local scopesBySource = {}

---@type table<Source, Source> source -> the player they last whispered with
local whisperPeers = {}

---@type table<integer, integer> userId -> os.time the mute expires, 0 = forever
local mutedUntil = {}

---@type table<Source, { tokens: number, updatedAt: number }>
local buckets = {}

-- --------------------------------------------------------------- utilities --

---@param source Source
---@return boolean
local function isStaff(source)
    return IsPlayerAceAllowed(source --[[@as string]], STAFF_ACE)
end

---@param source Source
---@return { color: string, text: string }?
local function getStaffLabel(source)
    for index = 1, #ROLES do
        local role = ROLES[index]

        if IsPlayerAceAllowed(source --[[@as string]], role.ace) then
            return { color = role.colour, text = role.label }
        end
    end

    return nil
end

---Resolves one of the player's colour choices to the hex the NUI paints
---with. Both are `chat_colors` items -- one is painted on the name and one on
---the message body -- and ui/server/uis/profile.lua stores each choice under
---its own metadata key. The equipped inventory slot is the fallback, since
---that is what an item-equip flow would set. 'rainbow' is a sentinel the NUI
---understands, so an item may carry that in place of a hex.
---@param source Source
---@param metadataKey 'name_color' | 'chat_text_color'
---@return string?
local function getChatColor(source, metadataKey)
    local itemId = core:GetMetadata(source, metadataKey)

    if not itemId then
        local inventory = core:GetInventorySnapshot(source)

        itemId = inventory and inventory.equipped and inventory.equipped.chat_colors
    end

    if not itemId then
        return nil
    end

    local item = core:GetItem(itemId)

    return item and (item.colour or item.data and item.data.colour) or nil
end

---@param source Source
---@return integer?
local function getPrestige(source)
    if GetResourceState('levels') ~= 'started' then
        return nil
    end

    local record = exports.levels:GetLevel(source)

    if not record or not record.prestige or record.prestige < 1 then
        return nil
    end

    return record.prestige
end

---@param source Source
---@return boolean
local function consumeToken(source)
    local now = os.clock()
    local bucket = buckets[source]

    if not bucket then
        bucket = { tokens = MESSAGE_BURST, updatedAt = now }
        buckets[source] = bucket
    end

    bucket.tokens = math.min(MESSAGE_BURST, bucket.tokens + (now - bucket.updatedAt) * MESSAGE_RATE)
    bucket.updatedAt = now

    if bucket.tokens < 1 then
        return false
    end

    bucket.tokens -= 1

    return true
end

---@param userId integer?
---@return boolean
local function isMuted(userId)
    if not userId then
        return false
    end

    local expiry = mutedUntil[userId]

    if not expiry then
        return false
    end

    if expiry ~= 0 and expiry <= os.time() then
        mutedUntil[userId] = nil

        return false
    end

    return true
end

---A line addressed to one player. Used for refusals, so a sender learns why
---nothing appeared rather than typing into a void.
---@param source Source
---@param text string
local function notify(source, text)
    TriggerClientEvent('gamechat:addMessage', source, {
        username = 'SERVER',
        userId = 0,
        modeId = 'announcement',
        text = text,
    })
end

---@param text string?
---@return string
local function trim(text)
    return type(text) == 'string' and (text:gsub('^%s+', ''):gsub('%s+$', '')) or ''
end

---Strips the control characters a client could smuggle through, collapses
---whitespace and clamps the length. The NUI renders text rather than HTML,
---so this is about keeping the log readable, not about escaping markup.
---@param text string
---@return string
local function sanitise(text)
    local cleaned = text:gsub('[%z\1-\8\11\12\14-\31]', ''):gsub('%s+', ' ')

    cleaned = trim(cleaned)

    if #cleaned > MAX_MESSAGE_LENGTH then
        cleaned = cleaned:sub(1, MAX_MESSAGE_LENGTH)
    end

    return cleaned
end

-- ------------------------------------------------------------------ scopes --

---@param source Source
---@param modeId string
---@return string?
local function getScope(source, modeId)
    local scopes = scopesBySource[source]

    return scopes and scopes[modeId] or nil
end

---Every player currently sharing `scopeId` in `modeId`.
---@param modeId string
---@param scopeId string
---@return Source[]
local function getScopeMembers(modeId, scopeId)
    local members = {}

    for _, playerSource in ipairs(core:GetPlayerSources()) do
        if getScope(playerSource, modeId) == scopeId then
            members[#members + 1] = playerSource
        end
    end

    return members
end

---Hopouts publishes no join/leave event, so rather than mirror its state this
---reads the match back on demand and writes it into the scope registry. A
---gamemode that calls SetPlayerScope itself wins: `__managed` marks the rows
---this function owns, and it only ever touches those.
---@param source Source
local function syncHopoutsScopes(source)
    if GetResourceState('hopouts') ~= 'started' then
        return
    end

    local scopes = scopesBySource[source]

    if scopes and not scopes.__managed and (scopes.game or scopes.team) then
        return
    end

    local matchId = exports.hopouts:GetMatchId(source)

    if not matchId then
        if scopes and scopes.__managed then
            scopes.game = nil
            scopes.team = nil
            scopes.__managed = nil
        end

        return
    end

    local summary = exports.hopouts:GetMatchSummary(matchId)
    local data = core:GetPlayerData(source)
    local userId = data and data.userId
    local rows = summary and summary.players or {}
    local side

    for index = 1, #rows do
        if rows[index].userId == userId then
            side = rows[index].side
            break
        end
    end

    scopes = scopesBySource[source] or {}
    scopesBySource[source] = scopes

    scopes.__managed = 'hopouts'
    scopes.game = ('match:%s'):format(matchId)
    scopes.team = side and ('match:%s:%s'):format(matchId, side) or nil
end

-- ------------------------------------------------------------------- modes --

---`available` gates the mode in the picker, `scope` is the bucket the sender
---is currently in, and `recipients` resolves that bucket to server ids. A
---mode with no `scope` is unscoped by nature and resolves against the whole
---server.
---@class GameChatModeDefinition
---@field id string
---@field label string
---@field available fun(source: Source): boolean
---@field scope? fun(source: Source): string?
---@field recipients fun(source: Source, scopeId: string?): Source[]

---@type table<string, GameChatModeDefinition>
local MODES = {}

---@type string[] picker order
local MODE_ORDER = { 'global_chat', 'local_chat', 'team', 'game', 'staff' }

MODES.global_chat = {
    id = 'global_chat',
    label = 'GLOBAL',
    available = function()
        return true
    end,
    recipients = function()
        return core:GetPlayerSources()
    end,
}

MODES.local_chat = {
    id = 'local_chat',
    label = 'LOCAL',
    available = function()
        return true
    end,
    recipients = function(source)
        local origin = GetEntityCoords(GetPlayerPed(source --[[@as string]]))
        local bucket = GetPlayerRoutingBucket(source --[[@as string]])
        local nearby = {}

        for _, playerSource in ipairs(core:GetPlayerSources()) do
            if GetPlayerRoutingBucket(playerSource --[[@as string]]) == bucket then
                local ped = GetPlayerPed(playerSource --[[@as string]])

                if ped ~= 0 and #(origin - GetEntityCoords(ped)) <= LOCAL_RADIUS then
                    nearby[#nearby + 1] = playerSource
                end
            end
        end

        return nearby
    end,
}

MODES.team = {
    id = 'team',
    label = 'TEAM',
    available = function(source)
        return getScope(source, 'team') ~= nil
    end,
    scope = function(source)
        return getScope(source, 'team')
    end,
    recipients = function(_, scopeId)
        return getScopeMembers('team', scopeId)
    end,
}

MODES.game = {
    id = 'game',
    label = 'GAME',
    available = function(source)
        return getScope(source, 'game') ~= nil
    end,
    scope = function(source)
        return getScope(source, 'game')
    end,
    recipients = function(_, scopeId)
        return getScopeMembers('game', scopeId)
    end,
}

MODES.staff = {
    id = 'staff',
    label = 'STAFF',
    available = isStaff,
    recipients = function()
        local staff = {}

        for _, playerSource in ipairs(core:GetPlayerSources()) do
            if isStaff(playerSource) then
                staff[#staff + 1] = playerSource
            end
        end

        return staff
    end,
}

---@param source Source
---@return { id: string, label: string, scopeId: string? }[]
local function buildModes(source)
    syncHopoutsScopes(source)

    local modes = {}

    for index = 1, #MODE_ORDER do
        local mode = MODES[MODE_ORDER[index]]

        if mode.available(source) then
            modes[#modes + 1] = {
                id = mode.id,
                label = mode.label,
                scopeId = mode.scope and mode.scope(source) or nil,
            }
        end
    end

    return modes
end

---Tells one client to pull a fresh picker. Called whenever something feeding
---`available` or `scope` changes underneath it.
---@param source Source
---@param forceSetToGame boolean?
local function refreshModes(source, forceSetToGame)
    TriggerClientEvent('gamechat:refreshModes', source, forceSetToGame == true)
end

-- ---------------------------------------------------------------- dispatch --

---@param source Source
---@param recipient Source
---@param modeId string
---@param scopeId string?
---@return 'ally' | 'enemy' | nil
local function getTeamRelation(source, recipient, modeId, scopeId)
    -- `game` is the only mode that mixes both sides into one channel, so it
    -- is the only one where a recipient needs telling which side the sender
    -- is on.
    if modeId ~= 'game' or not scopeId then
        return nil
    end

    local senderTeam = getScope(source, 'team')
    local recipientTeam = getScope(recipient, 'team')

    if not senderTeam or not recipientTeam then
        return nil
    end

    return senderTeam == recipientTeam and 'ally' or 'enemy'
end

---@param source Source
---@param modeId string
---@param text string
local function dispatch(source, modeId, text)
    local mode = MODES[modeId]
    local data = core:GetPlayerData(source)

    if not mode or not data then
        return
    end

    local scopeId = mode.scope and mode.scope(source) or nil

    if mode.scope and not scopeId then
        return notify(source, 'That channel is not available to you right now.')
    end

    local base = {
        username = data.username,
        userId = data.userId,
        modeId = modeId,
        scopeId = scopeId,
        text = text,
        nameColor = getChatColor(source, 'name_color'),
        textColor = getChatColor(source, 'chat_text_color'),
        staffLabel = getStaffLabel(source),
        prestige = getPrestige(source),
    }

    local recipients = mode.recipients(source, scopeId)

    for index = 1, #recipients do
        local recipient = recipients[index]
        local relation = getTeamRelation(source, recipient, modeId, scopeId)
        local message = base

        if relation then
            -- Copied only where it differs per recipient, so the common case
            -- stays one table shared by every TriggerClientEvent.
            message = {}

            for key, value in pairs(base) do
                message[key] = value
            end

            message.teamRelation = relation
        end

        TriggerClientEvent('gamechat:addMessage', recipient, message)
    end

    core:Log('chat', ('[%s] %s (%s): %s'):format(modeId, data.username, data.userId, text))
end

-- ---------------------------------------------------------------- requests --

RegisterNetEvent('gamechat:server:messageRequest', function(payload)
    local source = source --[[@as Source]]
    local data = core:GetPlayerData(source)

    if not data or type(payload) ~= 'table' then
        return
    end

    local modeId = type(payload.modeId) == 'string' and payload.modeId or 'global_chat'
    local mode = MODES[modeId]

    if not mode then
        return
    end

    syncHopoutsScopes(source)

    if not mode.available(source) then
        return notify(source, 'You cannot talk in that channel.')
    end

    local text = sanitise(type(payload.text) == 'string' and payload.text or '')

    if text == '' then
        return
    end

    if isMuted(data.userId) then
        return notify(source, 'You are muted.')
    end

    if not consumeToken(source) then
        return notify(source, 'Slow down.')
    end

    if core:ContainsProfanity(text) then
        return notify(source, 'That message was blocked.')
    end

    dispatch(source, modeId, text)
end)

lib.callback.register('gamechat:server:getAllowedModes', function(source)
    return buildModes(source)
end)

---Feeds the `@name` autocomplete. Everyone online is mentionable, and the
---list carries names and user ids only -- both of which the scoreboard
---already shows.
lib.callback.register('gamechat:server:getMentionablePlayers', function()
    local players = {}

    for _, playerSource in ipairs(core:GetPlayerSources()) do
        local data = core:GetPlayerData(playerSource)

        if data then
            players[#players + 1] = { userId = data.userId, username = data.username }
        end
    end

    return players
end)

-- --------------------------------------------------------------- whispers ---

---@param source Source
---@param target Source
---@param text string
local function sendWhisper(source, target, text)
    local from = core:GetPlayerData(source)
    local to = core:GetPlayerData(target)

    if not from or not to then
        return notify(source, 'No such player.')
    end

    if isMuted(from.userId) then
        return notify(source, 'You are muted.')
    end

    TriggerClientEvent('gamechat:addMessage', target, {
        username = from.username,
        userId = from.userId,
        modeId = 'whisper',
        text = text,
        nameColor = getChatColor(source, 'name_color'),
        textColor = getChatColor(source, 'chat_text_color'),
        staffLabel = getStaffLabel(source),
        whisperDirection = 'from',
        whisperPeerUsername = from.username,
    })

    TriggerClientEvent('gamechat:addMessage', source, {
        username = from.username,
        userId = from.userId,
        modeId = 'whisper',
        text = text,
        whisperDirection = 'to',
        whisperPeerUsername = to.username,
    })

    whisperPeers[source] = target
    whisperPeers[target] = source

    core:Log('chat', ('[whisper] %s (%s) -> %s (%s): %s'):format(
        from.username, from.userId, to.username, to.userId, text
    ))
end

lib.addCommand('w', {
    help = 'Whisper a player',
    params = {
        { name = 'target', type = 'playerId', help = 'server id' },
        { name = 'message', type = 'longString', help = 'what to say' },
    },
}, function(source, args)
    local text = sanitise(args.message)

    if text == '' then
        return notify(source, 'Usage: /w <id> <message>')
    end

    sendWhisper(source, args.target, text)
end)

lib.addCommand('r', {
    help = 'Reply to the last whisper',
    params = {
        { name = 'message', type = 'longString', help = 'what to say' },
    },
}, function(source, args)
    local target = whisperPeers[source]

    if not target or not core:GetPlayerData(target) then
        return notify(source, 'Nobody to reply to.')
    end

    local text = sanitise(args.message)

    if text == '' then
        return notify(source, 'Usage: /r <message>')
    end

    sendWhisper(source, target, text)
end)

-- -------------------------------------------------------------- moderation --

lib.addCommand('mute', {
    help = 'Stop a player using text chat',
    params = {
        { name = 'target', type = 'playerId', help = 'server id' },
        { name = 'minutes', type = 'number', help = '0 for until they reconnect', optional = true },
    },
    restricted = STAFF_ACE,
}, function(source, args)
    local data = core:GetPlayerData(args.target)

    if not data then
        return notify(source, 'No such player.')
    end

    local minutes = math.max(0, math.floor(args.minutes or 0))

    mutedUntil[data.userId] = minutes > 0 and (os.time() + minutes * 60) or 0

    notify(source, ('Muted %s%s.'):format(
        data.username, minutes > 0 and (' for %s minute(s)'):format(minutes) or ''
    ))
    notify(args.target, 'You have been muted in text chat.')

    core:Log('commands', ('[chat] %s muted %s (%s) for %s minute(s)'):format(
        source, data.username, data.userId, minutes
    ))
end)

lib.addCommand('unmute', {
    help = "Restore a player's text chat",
    params = {
        { name = 'target', type = 'playerId', help = 'server id' },
    },
    restricted = STAFF_ACE,
}, function(source, args)
    local data = core:GetPlayerData(args.target)

    if not data then
        return notify(source, 'No such player.')
    end

    mutedUntil[data.userId] = nil

    notify(source, ('Unmuted %s.'):format(data.username))
    notify(args.target, 'You can use text chat again.')
end)

lib.addCommand('clearchat', {
    help = "Clear every connected player's chat log",
    restricted = STAFF_ACE,
}, function(source)
    TriggerClientEvent('gamechat:clearMessages', -1)

    core:Log('commands', ('[chat] %s cleared chat'):format(source))
end)

lib.addCommand('announce', {
    help = 'Send a server-wide announcement',
    params = {
        { name = 'message', type = 'longString', help = 'what to announce' },
    },
    restricted = STAFF_ACE,
}, function(source, args)
    local text = sanitise(args.message)

    if text == '' then
        return notify(source, 'Usage: /announce <message>')
    end

    TriggerClientEvent('gamechat:addMessage', -1, {
        username = 'ANNOUNCEMENT',
        userId = 0,
        modeId = 'announcement',
        text = text,
    })

    core:Log('commands', ('[chat] %s announced: %s'):format(source, text))
end)

---The preference itself lives on the client, so this only flips it.
lib.addCommand('warmute', {
    help = 'Mute or unmute war announcements',
}, function(source)
    TriggerClientEvent('gamechat:toggleWarMute', source)
end)

-- ------------------------------------------------------------ suggestions ---

---@type GameChatSuggestion[]
local SUGGESTIONS = {
    {
        name = '/w',
        help = 'Whisper a player',
        params = {
            { name = 'id', help = 'server id' },
            { name = 'message', help = 'what to say' },
        },
    },
    {
        name = '/r',
        help = 'Reply to the last whisper',
        params = {
            { name = 'message', help = 'what to say' },
        },
    },
    {
        name = '/warmute',
        help = 'Mute or unmute war announcements',
    },
}

---@type GameChatSuggestion[]
local STAFF_SUGGESTIONS = {
    {
        name = '/mute',
        help = 'Stop a player using text chat',
        params = {
            { name = 'id', help = 'server id' },
            { name = 'minutes', help = '0 for until they reconnect' },
        },
    },
    {
        name = '/unmute',
        help = "Restore a player's text chat",
        params = {
            { name = 'id', help = 'server id' },
        },
    },
    {
        name = '/clearchat',
        help = "Clear every connected player's chat log",
    },
    {
        name = '/announce',
        help = 'Send a server-wide announcement',
        params = {
            { name = 'message', help = 'what to announce' },
        },
    },
}

---@param source Source
local function pushSuggestions(source)
    TriggerClientEvent('gamechat:addSuggestions', source, SUGGESTIONS)

    if isStaff(source) then
        TriggerClientEvent('gamechat:addSuggestions', source, STAFF_SUGGESTIONS)
    end
end

-- -------------------------------------------------------------- lifecycle ---

AddEventHandler('core:server:onPlayerLoaded', function(source)
    pushSuggestions(source)
    refreshModes(source, true)
end)

AddEventHandler('core:server:onPlayerDropped', function(source)
    scopesBySource[source] = nil
    buckets[source] = nil

    local peer = whisperPeers[source]

    if peer then
        whisperPeers[peer] = nil
    end

    whisperPeers[source] = nil
end)

-- ----------------------------------------------------------------- exports --

---Puts a player into a mode's scope, or takes them out of it with a nil
---scopeId. This is how a gamemode wires `team` and `game` up: give everyone
---in a match the same `game` scope and everyone on a side the same `team`
---scope, and the routing above follows.
---@param source Source
---@param modeId string
---@param scopeId string?
---@return boolean
exports('SetPlayerScope', function(source, modeId, scopeId)
    local mode = MODES[modeId]

    if not mode or not mode.scope then
        return false
    end

    local scopes = scopesBySource[source] or {}
    scopesBySource[source] = scopes

    if scopes[modeId] == scopeId then
        return true
    end

    scopes[modeId] = scopeId
    scopes.__managed = nil

    refreshModes(source, modeId == 'game' and scopeId ~= nil)

    return true
end)

---@param source Source
exports('ClearPlayerScopes', function(source)
    if not scopesBySource[source] then
        return
    end

    scopesBySource[source] = nil

    refreshModes(source, true)
end)

---@param source Source
---@param modeId string
---@return string?
exports('GetPlayerScope', function(source, modeId)
    return getScope(source, modeId)
end)

---A message from a resource rather than from a player. `target` is a server
---id, an array of them, or -1 for everyone.
---@param target Source | Source[]
---@param message GameChatMessage
---@return boolean
exports('SendMessage', function(target, message)
    if type(message) ~= 'table' or type(message.text) ~= 'string' then
        return false
    end

    local payload = {
        username = message.username or 'SERVER',
        userId = message.userId or 0,
        modeId = message.modeId or 'announcement',
        scopeId = message.scopeId,
        text = sanitise(message.text),
        textColor = message.textColor,
        nameColor = message.nameColor,
        chatTag = message.chatTag,
        gangLabel = message.gangLabel,
        staffLabel = message.staffLabel,
        prestige = message.prestige,
        teamRelation = message.teamRelation,
        action = message.action,
    }

    if payload.text == '' then
        return false
    end

    if type(target) == 'table' then
        for index = 1, #target do
            TriggerClientEvent('gamechat:addMessage', target[index], payload)
        end
    else
        TriggerClientEvent('gamechat:addMessage', target, payload)
    end

    return true
end)

---The war feed. `action` is what the NUI renders beside the name, and the
---client drops these entirely while the player has war announcements muted.
---@param username string
---@param action string
exports('Announce', function(username, action)
    TriggerClientEvent('gamechat:addMessage', -1, {
        username = username,
        userId = 0,
        modeId = 'announcement',
        text = action,
        action = action,
    })
end)

---@param source Source
---@param forceSetToGame boolean?
exports('RefreshModes', function(source, forceSetToGame)
    refreshModes(source, forceSetToGame)
end)

---@param userId integer
---@param minutes integer? 0 or nil mutes until they reconnect
exports('MutePlayer', function(userId, minutes)
    minutes = math.max(0, math.floor(minutes or 0))

    mutedUntil[userId] = minutes > 0 and (os.time() + minutes * 60) or 0
end)

---@param userId integer
exports('UnmutePlayer', function(userId)
    mutedUntil[userId] = nil
end)

---@param userId integer
---@return boolean
exports('IsPlayerMuted', function(userId)
    return isMuted(userId)
end)
