---Appearance persistence.
---
---core:UpdatePlayerAppearance on the client applies the look locally and then
---sends it here to be stored, so a reconnect gets the same character back.
---The server does not validate component ids against the ped: illenium
----appearance already clamps them, and duplicating that here would fight it.

local MAX_APPEARANCE_KEYS = 64

---@param appearance table
---@return boolean
local function isPlausibleAppearance(appearance)
    local count = 0

    for _ in pairs(appearance) do
        count += 1

        if count > MAX_APPEARANCE_KEYS then
            return false
        end
    end

    return count > 0
end

Core.guardEvent('core:server:saveAppearance', {
    burst = 5,
    rate = 0.5,
    args = { 'table' },
}, function(player, appearance)
    if not isPlausibleAppearance(appearance) then
        return
    end

    local ok, err = pcall(Core.db.saveAppearance, player.userId, appearance)

    if not ok then
        return lib.print.error(('[core] appearance save failed for %s: %s'):format(player.userId, err))
    end

    TriggerEvent('core:server:onAppearanceSaved', player.source, player.userId)
end)

lib.callback.register('core:server:getAppearance', function(source)
    local player = Core.getPlayer(source)

    if not player then
        return nil
    end

    local ok, appearance = pcall(Core.db.getAppearance, player.userId)

    return ok and appearance or nil
end)

---@param source Source
---@return table?
exports('GetAppearance', function(source)
    local player = Core.getPlayer(source)

    if not player then
        return nil
    end

    local ok, appearance = pcall(Core.db.getAppearance, player.userId)

    return ok and appearance or nil
end)

---The write half of GetAppearance, for resources that persist an appearance
---on the player's behalf (the appearance resource validates against its
---blacklist first, which is why it does not just let the client save).
---@param source Source
---@param appearance table
---@return boolean
exports('SaveAppearance', function(source, appearance)
    local player = Core.getPlayer(source)

    if not player or type(appearance) ~= 'table' or not next(appearance) then
        return false
    end

    local ok, err = pcall(Core.db.saveAppearance, player.userId, appearance)

    if not ok then
        lib.print.error(('[core] appearance save failed for %s: %s'):format(player.userId, err))

        return false
    end

    TriggerEvent('core:server:onAppearanceSaved', source, player.userId)

    return true
end)
