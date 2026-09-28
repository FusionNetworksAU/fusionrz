---Tournament callbacks.
---
---NOT IMPLEMENTED, same as base/server/events/gangs.lua. ui/client/uis/
---tournaments.lua calls these on menu open, and an unregistered ox_lib
---callback throws client-side. Registering them keeps the UI on its empty
---state instead.
---
---The read callbacks return nil, which every caller already passes straight
---through to the NUI layer. The write callbacks refuse with a message, so a
---player who reaches a button gets told rather than silently ignored.

local NOT_AVAILABLE = 'Tournaments are not available yet.'

for _, name in ipairs({
    'core:tournaments:requestOverview',
    'core:tournaments:requestTournaments',
    'core:tournaments:requestBracket',
    'core:tournaments:requestStandings',
    'core:tournaments:requestManage',
    'core:tournaments:staff:requestTeams',
}) do
    lib.callback.register(name, function()
        return nil
    end)
end

---@return table[]
lib.callback.register('core:tournaments:staff:searchPlayers', function()
    return {}
end)

---@return boolean success
---@return string error
lib.callback.register('core:tournaments:submitRoster', function()
    return false, NOT_AVAILABLE
end)

---@return boolean success
---@return string error
lib.callback.register('core:tournaments:withdrawRoster', function()
    return false, NOT_AVAILABLE
end)

---@return boolean success
---@return string error
lib.callback.register('core:tournaments:staff:action', function()
    return false, NOT_AVAILABLE
end)
