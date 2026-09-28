---Admin "live games" spectator callbacks.
---
---NOT IMPLEMENTED. These belong to a match/gamemode system that does not
---exist in this server yet, so there is nothing truthful to return. They are
---registered only so the admin menu stops raising "callback does not exist"
---on the client, and each returns the empty shape its caller expects.
---
---Replace the bodies once matches are running; the signatures are what
---ui/client/uis/admin.lua already relies on.

local NOT_AVAILABLE = 'Live games are not available yet.'

---@return table[]
lib.callback.register('ui:server:getAllLiveGames', function()
    return {}
end)

---@return table[]
lib.callback.register('ui:server:getLiveGamePlayers', function()
    return {}
end)

---@return boolean success
---@return string error
lib.callback.register('ui:server:viewLiveGame', function()
    return false, NOT_AVAILABLE
end)

---@return boolean success
lib.callback.register('ui:server:leaveLiveGame', function()
    return true
end)

---@return boolean success
---@return string error
lib.callback.register('ui:server:toggleGameFreeze', function()
    return false, NOT_AVAILABLE
end)
