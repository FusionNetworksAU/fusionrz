---Guard for net events.
---
---RegisterNetEvent hands you whatever the client sent, at whatever rate it
---felt like sending it. Core.guardEvent wraps a handler so the common three
---checks -- a loaded player, a sane call rate, and arguments of the declared
---shape -- happen before the body runs.

local DEFAULT_BURST = 10
local DEFAULT_RATE = 5

---@class GuardOptions
---@field burst integer? tokens available at once, default 10
---@field rate number? tokens restored per second, default 5
---@field requirePlayer boolean? default true
---@field args string[]? expected type() of each argument

---@param eventName string
---@param options GuardOptions
---@param handler fun(player: CorePlayer?, ...)
function Core.guardEvent(eventName, options, handler)
    -- Built on first use, not here: protection/*.lua is glob-loaded and
    -- events.lua sorts ahead of ratelimit.lua, so Core.createRateLimiter does
    -- not exist yet while this file is being read.
    local limiter
    local expectedArgs = options.args
    local requirePlayer = options.requirePlayer ~= false

    RegisterNetEvent(eventName, function(...)
        local source = source --[[@as Source]]

        local player = Core.getPlayer(source)

        if requirePlayer and not player then
            return
        end

        limiter = limiter or Core.createRateLimiter(options.burst or DEFAULT_BURST, options.rate or DEFAULT_RATE)

        if not limiter:consume(source) then
            return Core.flag(source, 'event-spam', eventName, 'protection_spam')
        end

        if expectedArgs then
            local args = { ... }

            for index = 1, #expectedArgs do
                if type(args[index]) ~= expectedArgs[index] then
                    return Core.flag(
                        source,
                        'event-args',
                        ('%s arg %s was %s, expected %s'):format(eventName, index, type(args[index]), expectedArgs[index])
                    )
                end
            end
        end

        handler(player, ...)
    end)
end

exports('GuardEvent', Core.guardEvent)
