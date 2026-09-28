---The roster tabs and the player info panel.
---
---The return shapes are dictated by the built NUI, which ships browser-mode
---fixtures for each of these calls -- those fixtures are the contract.
---Connected rows are { username, avatar, source, userId, role, activity },
---disconnected rows add { timestamp, reason }, and the info panel wants
---{ groups, playtimeSeconds, accountCreatedAt, discord, banHistory,
---  kickHistory, warningHistory, ping }.

local core = exports.core

---@return table[]
lib.callback.register('admin:server:getConnected', function(source)
    if not Admin.isStaff(source) then
        return {}
    end

    return Admin.getConnected()
end)

---@return table[]
lib.callback.register('admin:server:getDisconnected', function(source)
    if not Admin.isStaff(source) then
        return {}
    end

    return Admin.getDisconnected()
end)

---@param userId integer
---@return table
local function buildHistory(userId)
    return {
        banHistory = Admin.db.getBanHistory(userId),
        kickHistory = Admin.db.getActionHistory(userId, 'kick'),
        warningHistory = Admin.db.getActionHistory(userId, 'warn'),
    }
end

---qbx_core stores identifiers with their prefix, which is noise in a UI.
---@param value string?
---@param kind string
---@return string?
local function stripPrefix(value, kind)
    if type(value) ~= 'string' then
        return nil
    end

    return (value:gsub('^' .. kind .. ':', ''))
end

---@param userId integer
---@return table?
lib.callback.register('admin:server:getSelectedPlayerInfo', function(source, userId)
    if not Admin.isStaff(source) then
        return nil
    end

    userId = tonumber(userId) --[[@as integer]]

    if not userId then
        return nil
    end

    userId = math.floor(userId)

    local profile = Admin.db.getProfile(userId)
    local history = buildHistory(userId)
    local targetSource = Admin.resolveTarget(userId)
    local online = targetSource ~= nil and GetPlayerName(targetSource --[[@as string]]) ~= nil

    return {
        groups = online and Admin.getGroups(targetSource) or {},
        playtimeSeconds = profile.playtimeSeconds or 0,
        accountCreatedAt = Admin.toMillis(profile.accountCreatedAt),
        discord = profile.discord and { id = stripPrefix(profile.discord, 'discord') } or nil,
        banHistory = history.banHistory,
        kickHistory = history.kickHistory,
        warningHistory = history.warningHistory,
        ping = online and GetPlayerPing(targetSource --[[@as string]]) or 0,
    }
end)

---@param userId integer
---@return table?
lib.callback.register('admin:server:getSelectedDisconnectedInfo', function(source, userId)
    if not Admin.isStaff(source) then
        return nil
    end

    userId = tonumber(userId) --[[@as integer]]

    if not userId then
        return nil
    end

    userId = math.floor(userId)

    local profile = Admin.db.getProfile(userId)
    local history = buildHistory(userId)
    local entry = Admin.findDisconnected(userId)

    return {
        groups = {},
        playtimeSeconds = profile.playtimeSeconds or 0,
        -- The last session's length is not recorded anywhere and the roster
        -- entry only knows when they left, so this stays 0 rather than
        -- inventing a number the panel would show as fact.
        sessionPlaytimeSeconds = 0,
        accountCreatedAt = Admin.toMillis(profile.accountCreatedAt),
        discord = profile.discord and { id = stripPrefix(profile.discord, 'discord') } or nil,
        banHistory = history.banHistory,
        kickHistory = history.kickHistory,
        warningHistory = history.warningHistory,
        -- Already milliseconds: it comes off the roster entry, which stores
        -- it that way for the DISCONNECTED tab.
        lastSeen = entry and entry.timestamp or 0,
        lastReason = entry and entry.reason or 'Unknown',
    }
end)

---Used by the client half to populate its own player list without a second
---source of truth.
---@return table[]
exports('GetConnectedPlayers', function()
    return Admin.getConnected()
end)
