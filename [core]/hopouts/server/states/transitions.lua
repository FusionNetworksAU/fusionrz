Hopouts = Hopouts or {}
Hopouts.states = Hopouts.states or {}

local core = exports.core

Hopouts.states.lobby = {
    enter = function(match)
        Hopouts.broadcastRoster(match)
    end,
}

Hopouts.states.switchsides = {
    enter = function(match)
        Hopouts.swapSides(match)

        Hopouts.broadcast(match, 'hopouts:client:switchSides', {
            durationMsec = Hopouts.sharedConfig.switchSidesDurationMsec,
            offsets = Hopouts.sharedConfig.switchSideOffsets,
            scores = match.scores,
        })

        Hopouts.broadcastRoster(match)
    end,

    timeout = function(match)
        Hopouts.setState(match, 'preround', 5000)
    end,
}

-- --------------------------------------------------------------- matchend ----

Hopouts.states.matchend = {
    enter = function(match)
        -- A forfeit (server/forfeit.lua) decides it outright: the other team
        -- wins whatever the score was.
        local winningSide = Hopouts.getForfeitWinner(match) or Hopouts.getMatchWinner(match)

        if not winningSide then
            local standing = {}

            for index = 1, #match.sides do
                if #Hopouts.getPlayers(match, match.sides[index]) > 0 then
                    standing[#standing + 1] = match.sides[index]
                end
            end

            if #standing == 1 then
                winningSide = standing[1]
            end
        end

        Hopouts.clearLoadouts(match)
        Hopouts.despawnVehicles(match)
        Hopouts.pushScoreboard(match, winningSide)
        Hopouts.logResult(match, winningSide)

        local winners = {}

        if winningSide then
            for _, player in pairs(Hopouts.getPlayers(match, winningSide)) do
                winners[#winners + 1] = {
                    userId = player.userId,
                    username = player.username,
                    kills = player.kills,
                    deaths = player.deaths,
                    damage = player.damage,
                }
            end

            table.sort(winners, function(a, b) return a.kills > b.kills end)
        end

        Hopouts.broadcast(match, 'hopouts:client:matchEnd', {
            winningSide = winningSide,
            scores = match.scores,
            winners = winners,
            previewDurationMsec = Hopouts.sharedConfig.winnerPreviewDurationMsec,
            offsets = Hopouts.sharedConfig.winnerPreviewOffsets,
        })

        Hopouts.recordStats(match, winningSide)

        TriggerEvent('hopouts:server:matchApplied', match.id, {
            mapId = match.map.id,
            scores = match.scores,
            winningSide = winningSide,
            players = Hopouts.buildScoreboard(match),
        })
    end,

    timeout = function(match)
        Hopouts.destroyMatch(match.id, 'match ended')
    end,
}
