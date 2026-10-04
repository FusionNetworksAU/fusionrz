---Private lobby + war callbacks (K menu > Lobbies).
---
---NOT IMPLEMENTED, same as core/base/server/events/tournaments.lua: there is
---no server half for private lobbies or wars yet. ui/client/uis/lobbies.lua
---calls these as soon as the Lobbies page opens, and an unregistered ox_lib
---callback throws client-side, so they are registered to keep the page on its
---empty state.
---
---Lists come back as empty tables, never nil: getAllLobbies / getAllWars /
---getWarMaps hand the reply straight to the NUI, which maps over it. Actions
---refuse with a message so a player who presses a button is told why.
---
---uis:server:getRankedLobbyMaps lives in lobbies.lua and is real.

local NOT_AVAILABLE = 'Private lobbies are not available yet.'

for _, name in ipairs({
    'uis:server:getAllLobbies',
    'uis:server:getAllWars',
    'uis:server:getLobbyPlayers',
    'uis:server:getWarMaps',
    'uis:server:getGamemodeMaps',
    'uis:server:getFfaMaps',
}) do
    lib.callback.register(name, function()
        return {}
    end)
end

for _, name in ipairs({
    'uis:server:createLobby',
    'uis:server:joinLobby',
    'uis:server:deleteMyLobby',
    'uis:server:leaveLobby',
    'uis:server:kickLobbyPlayer',
    'uis:server:setPlayerTeam',
    'uis:server:setLobbySlots',
    'uis:server:updateLobbyConfig',
    'uis:server:startLobbyGame',
    'uis:server:createWar',
    'uis:server:spectateWar',
    'uis:server:warStepIn',
    'uis:server:warStepOut',
    'uis:server:announceWar',
    'uis:server:setWarMap',
    'uis:server:startWarMapVote',
    'uis:server:castWarMapVote',
    'uis:server:restartWarRound',
    'uis:server:toggleWarFreeze',
}) do
    lib.callback.register(name, function()
        return false, NOT_AVAILABLE
    end)
end

-- The browse page announces itself so a live implementation can push list
-- updates to whoever is looking. Nothing to push yet.
RegisterNetEvent('uis:server:lobbiesBrowseOpened', function() end)
RegisterNetEvent('uis:server:lobbiesBrowseClosed', function() end)
