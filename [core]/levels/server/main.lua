local config = require 'config.shared' ---@type LevelsSharedConfig
local core = exports.core

---@class LevelRecord
---@field level integer
---@field xp integer
---@field prestige integer

---@type table<integer, LevelRecord> userId -> record
local records = {}

---@param userId integer
---@return LevelRecord
local function fetch(userId)
    local row = MySQL.single.await('SELECT level, xp, prestige FROM user_levels WHERE user_id = ?', { userId })

    if not row then
        MySQL.insert.await('INSERT IGNORE INTO user_levels (user_id) VALUES (?)', { userId })

        return { level = 1, xp = 0, prestige = 0 }
    end

    return {
        level = row.level or 1,
        xp = row.xp or 0,
        prestige = row.prestige or 0,
    }
end

---@param userId integer
---@param record LevelRecord
local function persist(userId, record)
    MySQL.update.await(
        'UPDATE user_levels SET level = ?, xp = ?, prestige = ? WHERE user_id = ?',
        { record.level, record.xp, record.prestige, userId }
    )
end

---@param source Source
---@return integer? userId
local function getUserId(source)
    local data = core:GetPlayerData(source)

    return data and data.userId or nil
end

---@param source Source
---@return LevelRecord?
local function getRecord(source)
    local userId = getUserId(source)

    if not userId then
        return nil
    end

    if not records[userId] then
        local ok, record = pcall(fetch, userId)

        if not ok then
            lib.print.error(('[levels] fetch failed for %s: %s'):format(userId, record))

            return nil
        end

        records[userId] = record
    end

    return records[userId]
end

---@param source Source
---@param record LevelRecord
local function push(source, record)
    TriggerClientEvent('levels:client:state', source, record.level, record.xp, record.prestige)

    Player(source).state:set('careerLevel', record.level, true)
    Player(source).state:set('careerPrestige', record.prestige, true)
end

---@param record LevelRecord
---@return integer levelsGained
local function applyLevels(record)
    local gained = 0

    while record.level < config.maxLevel do
        local needed = config.xpForNext(record.level)

        if record.xp < needed then
            break
        end

        record.xp -= needed
        record.level += 1
        gained += 1
    end

    -- At max level xp stops accumulating rather than counting toward a level
    -- that does not exist; prestige is the only way onward.
    if record.level >= config.maxLevel then
        record.level = config.maxLevel
        record.xp = 0
    end

    return gained
end

---@param source Source
---@param amount integer
---@param reason string?
---@return boolean success
---@return integer? level
local function addXp(source, amount, reason)
    amount = tonumber(amount) and math.floor(amount) or 0

    if amount <= 0 then
        return false
    end

    local record = getRecord(source)
    local userId = getUserId(source)

    if not record or not userId then
        return false
    end

    if record.level >= config.maxLevel then
        return true, record.level
    end

    record.xp += amount

    local gained = applyLevels(record)

    persist(userId, record)
    push(source, record)

    if gained > 0 then
        TriggerClientEvent('levels:client:levelUp', source, record.level, gained)
        TriggerEvent('levels:server:onLevelUp', source, record.level, gained)

        core:Log('commands', ('[levels] %s reached level %s'):format(userId, record.level))
    end

    TriggerEvent('levels:server:onXpGained', source, amount, reason)

    return true, record.level
end

exports('AddXp', addXp)

---The named awards from config/shared.lua, so callers ask for "a kill"
---rather than hardcoding a number that then drifts from the config.
---@param source Source
---@param kind 'kills' | 'headshots' | 'wins' | 'losses'
---@param count integer?
---@return boolean
exports('Award', function(source, kind, count)
    local amount = config.xp[kind]

    if not amount then
        return false
    end

    return addXp(source, amount * (count or 1), kind)
end)

---@param source Source
---@return LevelRecord?
exports('GetLevel', function(source)
    local record = getRecord(source)

    return record and { level = record.level, xp = record.xp, prestige = record.prestige } or nil
end)

---@param userId integer
---@return LevelRecord?
exports('GetLevelByUserId', function(userId)
    if records[userId] then
        return records[userId]
    end

    local ok, record = pcall(fetch, userId)

    return ok and record or nil
end)

-- -------------------------------------------------------------- prestige ----

---@param source Source
---@return string? denyReason one of the DENY keys the client knows
local function checkPrestige(source)
    local record = getRecord(source)

    if not record then
        return 'level'
    end

    if record.prestige >= config.maxPrestige then
        return 'max_prestige'
    end

    if record.level < config.maxLevel then
        return 'level'
    end

    -- The Reaper is at spawn, and prestiging mid-match would reset a player
    -- other people are currently playing against.
    if GetResourceState('hopouts') == 'started' and exports.hopouts:GetMatchId(source) then
        return 'in_match'
    end

    return nil
end

---@return string? denyReason
lib.callback.register('levels:server:canPrestige', function(source)
    return checkPrestige(source)
end)

---@return string? denyReason
lib.callback.register('levels:server:prestige', function(source)
    -- Re-checked rather than trusting the canPrestige the client just did:
    -- the two calls are seconds apart with a cutscene in between.
    local denied = checkPrestige(source)

    if denied then
        return denied
    end

    local record = getRecord(source)
    local userId = getUserId(source)

    if not record or not userId then
        return 'level'
    end

    record.prestige += 1
    record.level = 1
    record.xp = 0

    persist(userId, record)
    push(source, record)

    TriggerEvent('levels:server:onPrestige', source, record.prestige)

    core:Log('commands', ('[levels] %s prestiged to %s'):format(userId, record.prestige))

    return nil
end)

-- ------------------------------------------------------------- lifecycle ----

AddEventHandler('core:server:onPlayerLoaded', function(source)
    CreateThread(function()
        local record = getRecord(source)

        if record then
            push(source, record)
        end
    end)
end)

AddEventHandler('core:server:onPlayerDropped', function(_, userId)
    records[userId] = nil
end)

lib.addCommand('addxp', {
    help = 'Give a player XP',
    params = {
        { name = 'target', type = 'playerId', help = 'server id' },
        { name = 'amount', type = 'number', help = 'xp to add' },
    },
    restricted = 'group.admin',
}, function(source, args)
    local ok, level = addXp(args.target, args.amount, ('staff:%s'):format(source))

    TriggerClientEvent('chat:addMessage', source, {
        args = { 'levels', ok and ('Now level %s.'):format(level) or 'Could not award XP.' },
    })
end)
