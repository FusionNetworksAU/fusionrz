---Push topics.
---
---A client that has a menu open subscribes to a topic and gets pushed updates
---while it stays open; everyone else costs nothing. The UI calls
---core:Subscribe('teleportCounts') / core:Unsubscribe(...) from
---ui/client/uis/menu.lua.

local broadcast = require 'modules.broadcast'

---@class SubscriptionTopic
---@field intervalMs integer? nil = push only when something changes
---@field build fun(): any
---@field event string

---@type table<string, SubscriptionTopic>
local topics = {}

---@type table<string, table<Source, true>>
local subscribers = {}

---@type table<string, boolean>
local pending = {}

---@param name string
---@param topic SubscriptionTopic
function Core.registerTopic(name, topic)
    topics[name] = topic
    subscribers[name] = subscribers[name] or {}

    if topic.intervalMs and topic.intervalMs > 0 then
        CreateThread(function()
            while topics[name] do
                Wait(topic.intervalMs)

                if next(subscribers[name]) then
                    Core.publishTopic(name)
                end
            end
        end)
    end
end

---@param name string
---@param source Source
---@return boolean
function Core.subscribe(name, source)
    local topic = topics[name]

    if not topic then
        return false
    end

    subscribers[name][source] = true

    -- Send the current value straight away, otherwise a menu that just opened
    -- sits empty until the next interval tick.
    TriggerClientEvent(topic.event, source, topic.build())

    return true
end

---@param name string
---@param source Source
function Core.unsubscribe(name, source)
    local topicSubscribers = subscribers[name]

    if topicSubscribers then
        topicSubscribers[source] = nil
    end
end

---@param source Source
function Core.unsubscribeAll(source)
    for _, topicSubscribers in pairs(subscribers) do
        topicSubscribers[source] = nil
    end
end

---@param name string
function Core.publishTopic(name)
    local topic = topics[name]
    local topicSubscribers = subscribers and subscribers[name]

    if not topic or not topicSubscribers or not next(topicSubscribers) then
        return
    end

    broadcast.triggerClientEvent(topic.event, topicSubscribers, broadcast.resolveKey, topic.build())
end

---Coalesces a burst of changes into one push on the next frame. Twenty
---players walking through a teleport in the same tick should be one message,
---not twenty.
---@param name string
function Core.invalidateTopic(name)
    if pending[name] then
        return
    end

    pending[name] = true

    SetTimeout(0, function()
        pending[name] = nil

        Core.publishTopic(name)
    end)
end

RegisterNetEvent('core:server:subscribe', function(name)
    local source = source --[[@as Source]]

    if type(name) ~= 'string' or not Core.getPlayer(source) then
        return
    end

    Core.subscribe(name, source)
end)

RegisterNetEvent('core:server:unsubscribe', function(name)
    local source = source --[[@as Source]]

    if type(name) ~= 'string' then
        return
    end

    Core.unsubscribe(name, source)
end)

exports('RegisterTopic', Core.registerTopic)
exports('PublishTopic', Core.publishTopic)
exports('InvalidateTopic', Core.invalidateTopic)
