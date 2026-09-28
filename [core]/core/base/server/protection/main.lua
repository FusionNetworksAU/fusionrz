---Detection bookkeeping shared by the detectors in this folder.
---
---Detectors call Core.flag. What a flag does is policy, set by convar, so a
---false positive on a live server is a convar change rather than a restart
---with a code edit.

---@alias ProtectionAction 'log' | 'kick' | 'ban'

local ACTION = GetConvar('core:protectionAction', 'log') --[[@as ProtectionAction]]
local STRIKE_LIMIT = GetConvarInt('core:protectionStrikes', 3)
local STRIKE_WINDOW = GetConvarInt('core:protectionStrikeWindow', 120)
local BAN_SECONDS = GetConvarInt('core:protectionBanSeconds', 0)

---@type table<Source, { count: integer, firstAt: integer }>
local strikes = {}

---@param source Source
---@return integer count
local function addStrike(source)
    local now = os.time()
    local record = strikes[source]

    if not record or now - record.firstAt > STRIKE_WINDOW then
        record = { count = 0, firstAt = now }
        strikes[source] = record
    end

    record.count += 1

    return record.count
end

---@param source Source
---@param detector string
---@param detail string
---@param reasonKey DropReasonKey?
function Core.flag(source, detector, detail, reasonKey)
    local player = Core.getPlayer(source)
    local label = player and ('%s (%s)'):format(player.username, player.userId) or ('src %s'):format(source)
    local count = addStrike(source)

    Core.log('protection', ('[%s] %s: %s (strike %s/%s)'):format(detector, label, detail, count, STRIKE_LIMIT))

    TriggerEvent('core:server:onProtectionFlag', source, detector, detail, count)

    if ACTION == 'log' or count < STRIKE_LIMIT then
        return
    end

    strikes[source] = nil

    if ACTION == 'ban' then
        exports.core:BanPlayer(source, ('anti-cheat: %s'):format(detector), BAN_SECONDS > 0 and BAN_SECONDS or nil, 'SYSTEM')

        return
    end

    Core.dropWithReason(source, reasonKey or 'protection_event', detector)
end

---@param source Source
function Core.clearStrikes(source)
    strikes[source] = nil
end

AddEventHandler('playerDropped', function()
    strikes[source --[[@as Source]]] = nil
end)

exports('Flag', Core.flag)
