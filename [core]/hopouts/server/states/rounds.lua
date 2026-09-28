---The round states: warmup, preround, live, roundend.
---
---Each state is { enter, tick?, timeout? }. `timeout` fires once when the
---duration given to setState runs out; `tick` runs every engine tick (250ms)
---while the state is current. A state with neither ends itself from an
---event, which is how `live` works -- it is a wipe that ends a round, not a
---clock, unless the clock runs out first.

Hopouts = Hopouts or {}
Hopouts.states = Hopouts.states or {}

local core = exports.core

---@param match HopOutMatch
local function spawnEveryone(match)
    for playerSource, player in pairs(match.players) do
        local coords = Hopouts.getSpawn(match, player)

        player.alive = true

        if coords then
            TriggerClientEvent('hopouts:client:spawn', playerSource, {
                coords = coords,
                frozen = true,
            })
        end
    end
end

-- ---------------------------------------------------------------- warmup ----

Hopouts.states.warmup = {
    enter = function(match)
        match.round = 0

        spawnEveryone(match)
        Hopouts.broadcastRoster(match)
    end,

    timeout = function(match)
        Hopouts.setState(match, 'preround', 5000)
    end,
}

-- -------------------------------------------------------------- preround ----

---Frozen at spawn with the round's kit already applied, so the round starts
---the instant the freeze lifts rather than while people are still equipping.
Hopouts.states.preround = {
    enter = function(match)
        match.round += 1

        Hopouts.resetRoundStats(match)
        spawnEveryone(match)
        Hopouts.applyLoadouts(match)
        Hopouts.spawnVehicles(match)
        Hopouts.broadcastRoster(match)

        Hopouts.broadcast(match, 'hopouts:client:preround', {
            round = match.round,
            pistolOnly = Hopouts.isPistolRound(match),
        })
    end,

    timeout = function(match)
        Hopouts.setState(match, 'live', Hopouts.sharedConfig.timeoutDurationMsec)
    end,
}

-- ------------------------------------------------------------------ live ----

Hopouts.states.live = {
    enter = function(match)
        Hopouts.broadcast(match, 'hopouts:client:live', {
            round = match.round,
            durationMsec = Hopouts.sharedConfig.timeoutDurationMsec,
        })

        -- The closing, moving zone for this round (server/zone.lua).
        Hopouts.startZone(match)
    end,

    ---Ends the moment one side is the only one left. Checked on the tick
    ---rather than on each kill so a trade that wipes both sides in the same
    ---frame resolves once, as a draw, instead of twice.
    tick = function(match)
        local survivor = Hopouts.getLastSideStanding(match)

        if survivor then
            -- On the match, not match.data: setState clears data before it
            -- calls enter, so roundend would read nil.
            match.roundWinner = survivor

            return Hopouts.setState(match, 'roundend', Hopouts.sharedConfig.scoreboardDisplayTimeMsec)
        end

        local anyoneAlive = false

        for _, player in pairs(match.players) do
            if player.alive then
                anyoneAlive = true
                break
            end
        end

        if not anyoneAlive and next(match.players) then
            match.roundWinner = nil

            Hopouts.setState(match, 'roundend', Hopouts.sharedConfig.scoreboardDisplayTimeMsec)
        end
    end,

    ---The round clock running out is a draw: nobody closed it out.
    timeout = function(match)
        match.roundWinner = nil

        Hopouts.setState(match, 'roundend', Hopouts.sharedConfig.scoreboardDisplayTimeMsec)
    end,
}

-- -------------------------------------------------------------- roundend ----

---How long the round MVP card has the screen before the scoreboard replaces
---it. The rest of scoreboardDisplayTimeMsec (13s) is the scoreboard's.
local MVP_DISPLAY_MSEC = 4000

Hopouts.states.roundend = {
    enter = function(match)
        local winningSide = match.roundWinner

        if winningSide then
            Hopouts.awardRound(match, winningSide)
        end

        Hopouts.clearLoadouts(match)
        Hopouts.despawnVehicles(match)

        -- The MVP card first, on its own, then the scoreboard once it has
        -- gone. They used to go out together and the card sat on top of the
        -- scoreboard for the whole round end.
        local mvp = Hopouts.getRoundMvp(match)

        if mvp then
            mvp.won = winningSide ~= nil and mvp.side == winningSide
            mvp.displayMsec = MVP_DISPLAY_MSEC

            Hopouts.broadcast(match, 'hopouts:client:roundMvp', mvp)

            local round = match.round

            SetTimeout(MVP_DISPLAY_MSEC, function()
                -- Still this round's end (not a new round, or a finished match).
                if match.state == 'roundend' and match.round == round then
                    Hopouts.pushScoreboard(match, winningSide)
                end
            end)
        else
            Hopouts.pushScoreboard(match, winningSide)
        end

        Hopouts.broadcast(match, 'hopouts:client:roundEnd', {
            round = match.round,
            winningSide = winningSide,
            scores = match.scores,
        })

        TriggerEvent('hopouts:server:onRoundEnded', match.id, match.round, winningSide)
    end,

    timeout = function(match)
        if Hopouts.getMatchWinner(match) then
            return Hopouts.setState(match, 'matchend', Hopouts.sharedConfig.winnerPreviewDurationMsec)
        end

        -- Halftime: the swap happens between rounds so the next preround
        -- spawns everyone on their new side already.
        if #match.sides == 2 and match.round == match.roundsPerHalf and not match.swapped then
            return Hopouts.setState(match, 'switchsides', Hopouts.sharedConfig.switchSidesDurationMsec)
        end

        Hopouts.setState(match, 'preround', 5000)
    end,
}
