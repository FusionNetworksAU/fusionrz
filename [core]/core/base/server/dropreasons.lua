---@alias DropReasonKey
---| 'protection_event'
---| 'protection_weapon'
---| 'protection_explosion'
---| 'protection_entity'
---| 'protection_spam'
---| 'no_player_loaded'
---| 'duplicate_session'
---| 'server_restart'
---| 'invalid_state'

---@type table<DropReasonKey, string>
local reasons = {
    protection_event = 'Disconnected by anti-cheat: a network event was sent that the client cannot legitimately send.',
    protection_weapon = 'Disconnected by anti-cheat: an unauthorised weapon was detected.',
    protection_explosion = 'Disconnected by anti-cheat: a blocked explosion was triggered.',
    protection_entity = 'Disconnected by anti-cheat: an unauthorised entity was created.',
    protection_spam = 'Disconnected by anti-cheat: you sent server events faster than the server accepts them.',
    no_player_loaded = 'Your account was not loaded. Please reconnect.',
    duplicate_session = 'Your account was loaded in another session.',
    server_restart = 'The server is restarting.',
    invalid_state = 'Your session entered an invalid state. Please reconnect.',
}

Core.dropReasons = reasons

---@param key DropReasonKey
---@param detail string?
---@return string
function Core.getDropReason(key, detail)
    local reason = reasons[key] or reasons.invalid_state

    if detail then
        return ('%s\n(%s)'):format(reason, detail)
    end

    return reason
end

---@param source Source
---@param key DropReasonKey
---@param detail string?
function Core.dropWithReason(source, key, detail)
    local player = Core.getPlayer(source)

    if player then
        pcall(player.save, player, true)
    end

    Core.log('protection', ('dropped %s (%s): %s'):format(
        player and player.username or 'unknown',
        source,
        detail or key
    ))

    DropPlayer(source --[[@as string]], Core.getDropReason(key, detail))
end

exports('DropWithReason', Core.dropWithReason)
