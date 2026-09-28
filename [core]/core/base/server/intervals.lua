---Periodic background work. Every interval is convar-tunable so a busy server
---can back them off without a code change.

local SAVE_INTERVAL = GetConvarInt('core:saveIntervalSeconds', 300) * 1000
local ITEM_REFRESH_INTERVAL = GetConvarInt('core:itemRefreshSeconds', 900) * 1000

---Saves are spread across the interval rather than fired in one burst: a
---hundred players hitting the same tick is a hundred round trips landing at
---once, which is exactly the stall the interval exists to avoid.
local function saveLoop()
    while true do
        Wait(SAVE_INTERVAL)

        local players = Core.getPlayers()
        local count = Core.getPlayerCount()

        if count > 0 then
            local spacing = math.max(50, SAVE_INTERVAL // (count * 4))

            for _, player in pairs(players) do
                local ok, err = pcall(player.save, player)

                if not ok then
                    lib.print.error(('[core] save failed for %s: %s'):format(player.userId, err))
                end

                Wait(spacing)
            end
        end
    end
end

local function itemRefreshLoop()
    while true do
        Wait(ITEM_REFRESH_INTERVAL)

        local ok, err = pcall(Core.refreshItems)

        if not ok then
            lib.print.error(('[core] item refresh failed: %s'):format(err))
        end
    end
end

Core.onReady(function()
    CreateThread(saveLoop)

    if ITEM_REFRESH_INTERVAL > 0 then
        CreateThread(itemRefreshLoop)
    end
end)

---txAdmin announces a scheduled restart before it happens. Flipping this flag
---is what makes the deferral in main.lua turn new connections away with the
---'restart' locale instead of letting them load into a server that is about
---to go down.
AddEventHandler('txAdmin:events:scheduledRestart', function(payload)
    if type(payload) ~= 'table' or payload.secondsRemaining == nil then
        return
    end

    if payload.secondsRemaining <= 60 then
        Core.isRestarting = true
    end
end)

AddEventHandler('txAdmin:events:serverShuttingDown', function()
    Core.isRestarting = true

    for _, player in pairs(Core.getPlayers()) do
        pcall(player.save, player, true)
    end
end)
