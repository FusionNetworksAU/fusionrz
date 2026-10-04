---Callbacks owned by resources this server does not run.
---
---ui ships the pages for the battle pass, war pass, live events and weapon
---charms, but their server halves live in separate resources (battlepass,
---warpass, events, weaponcosmetics) that are not installed. Every button on
---those pages awaits one of the callbacks below, and an unregistered ox_lib
---callback throws client-side and leaves the button hanging.
---
---Each block only registers when its owning resource is missing entirely, so
---installing the real resource later takes over without the two racing to
---answer (ui needs a restart once it is added).
---
---Reply shapes match what ui/client/uis/*.lua and the NUI read:
---  battlepass / warpass:  success:boolean, failReason:string
---  events:server:claim:   { ok = false, error = <key in events.lua claimErrors> }
---  events:admin:*:        { ok = false, error = string } (the admin panel checks .ok)

---@param resource string
---@return boolean
local function isMissing(resource)
    return GetResourceState(resource) == 'missing'
end

---@param names string[]
---@param handler function
local function registerAll(names, handler)
    for index = 1, #names do
        lib.callback.register(names[index], handler)
    end
end

if isMissing('battlepass') then
    registerAll({
        'battlepass:server:purchasePass',
        'battlepass:server:upgradeLevel',
        'battlepass:server:rerollQuest',
        'battlepass:server:giftPass',
    }, function()
        return false, 'The battle pass is not available yet.'
    end)
end

if isMissing('warpass') then
    registerAll({
        'warpass:server:purchasePass',
        'warpass:server:upgradeLevel',
        'warpass:server:giftPass',
    }, function()
        return false, 'The war pass is not available yet.'
    end)
end

if isMissing('events') then
    local NOT_AVAILABLE = 'Events are not available on this server.'

    lib.callback.register('events:server:scoreboard', function()
        return false
    end)

    lib.callback.register('events:server:claim', function()
        return { ok = false, error = 'not_live' }
    end)

    lib.callback.register('events:admin:items', function()
        return { ok = false, error = NOT_AVAILABLE, items = {}, truncated = false }
    end)

    lib.callback.register('events:admin:uploadUrl', function()
        return { ok = false, error = 'uploads_unavailable' }
    end)

    registerAll({
        'events:admin:list',
        'events:admin:get',
        'events:admin:save',
        'events:admin:publish',
        'events:admin:end',
        'events:admin:archive',
        'events:admin:delete',
    }, function()
        return { ok = false, error = NOT_AVAILABLE }
    end)
end

if isMissing('weaponcosmetics') then
    lib.callback.register('weaponcosmetics:server:equipCharm', function()
        return false
    end)
end
