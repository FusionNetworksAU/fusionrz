---Solo test commands.
---
---Modelled on `@hopouts/server/debug/commands.lua`: registered only when the
---convar is on, so they cannot be reached on a live server by accident. Turn
---them on with `setr gamemodes_debug 1` in server.cfg.

if GetConvarInt('gamemodes_debug', 0) ~= 1 then
    return
end

---`ui` exposes notify to the client only; `uis:notify` is the net event it
---registers for exactly this, so the server reaches it that way.
---@param source Source
---@param message string
local function reply(source, message)
    if source == 0 then
        print(('[gamemodes] %s'):format(message))

        return
    end

    TriggerClientEvent('uis:notify', source, { type = 'inform', text = message, duration = 5000 })
    print(('[gamemodes] (%d) %s'):format(source, message))
end

---@return string
local function modeList()
    local names = {}

    for mode in pairs(Gamemodes.definitions) do
        names[#names + 1] = mode
    end

    table.sort(names)

    return table.concat(names, ', ')
end

---`/gm <mode|portal>` - drop straight into a mode, skipping the menu and the
---preview. This is the one you want for solo testing.
RegisterCommand('gm', function(source, args)
    if source == 0 then
        return reply(source, 'run /gm in game, it needs a player')
    end

    local target = args[1]

    if not target then
        return reply(source, ('usage: /gm <mode>  |  modes: %s'):format(modeList()))
    end

    if not Gamemodes.resolveMode(target) then
        return reply(source, ('unknown mode "%s". modes: %s'):format(target, modeList()))
    end

    -- enterModeImmediate skips the preview screen and the "press E" step.
    TriggerClientEvent('gamemodes:dev:enterImmediate', source, target)
end, false)

---`/gmleave` - leave whatever round you are in.
RegisterCommand('gmleave', function(source)
    local id = exports.gamemodes:getPlayerInstance(source)

    if not id then
        return reply(source, 'you are not in a gamemode')
    end

    TriggerClientEvent('gamemodes:cleanup', source, true)
    reply(source, ('left %s'):format(id))
end, false)

---`/gmend` - force the current round to the podium, to test round end without
---grinding out the kill target.
RegisterCommand('gmend', function(source)
    local instances = exports.gamemodes:getInstances()
    local id = exports.gamemodes:getPlayerInstance(source)
    local instance = id and instances[id]

    if not instance then
        return reply(source, 'you are not in a gamemode')
    end

    Gamemodes.endMatch(instance)
    reply(source, ('ended %s'):format(id))
end, false)

---`/gmkill [n]` - credit yourself n kills. Drives the stats bar, the top 3 and
---the win condition without needing a second player, which is the whole point
---of testing solo.
RegisterCommand('gmkill', function(source, args)
    local instances = exports.gamemodes:getInstances()
    local id = exports.gamemodes:getPlayerInstance(source)
    local instance = id and instances[id]

    if not instance then
        return reply(source, 'you are not in a gamemode')
    end

    local count = math.max(1, math.tointeger(tonumber(args[1]) or 1) or 1)

    for _ = 1, count do
        local score = instance.scores[source]

        if score then
            score.kills += 1
        end

        Gamemodes.getHandler(instance.def).onKill(instance, source, nil, false)

        if instance.phase ~= 'live' then
            break
        end
    end

    Gamemodes.pushStats(instance, source)
    reply(source, ('credited %d kill(s) in %s'):format(count, id))
end, false)

---`/gmstatus` - what is running right now, printed to the server console too.
RegisterCommand('gmstatus', function(source)
    local instances = exports.gamemodes:getInstances()
    local lines = {}

    for id, instance in pairs(instances) do
        local count = 0

        for _ in pairs(instance.players) do
            count += 1
        end

        lines[#lines + 1] = ('%s  mode=%s  map=%s  phase=%s  players=%d  endsIn=%ds')
            :format(id, instance.mode, instance.map.id, instance.phase, count,
                math.max(0, (instance.endsAt - GetGameTimer()) // 1000))
    end

    if #lines == 0 then
        return reply(source, 'no gamemode instances running')
    end

    for index = 1, #lines do
        reply(source, lines[index])
    end
end, false)

---`/gmmaps` - list the map pool ids for a mode, so you can check the pools
---resolve before entering.
RegisterCommand('gmmaps', function(source, args)
    local mode = Gamemodes.resolveMode(args[1] or '')

    if not mode then
        return reply(source, ('usage: /gmmaps <mode>  |  modes: %s'):format(modeList()))
    end

    local pool = require('shared.location_pools').get(mode)
    local ids = {}

    for index = 1, #pool do
        ids[#ids + 1] = ('%s(%d spawns)'):format(pool[index].id, #pool[index].spawns)
    end

    reply(source, ('%s: %s'):format(mode, table.concat(ids, ', ')))
end, false)

print('[gamemodes] debug commands registered: /gm /gmleave /gmend /gmkill /gmstatus /gmmaps')
