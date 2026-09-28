Hopouts = Hopouts or {}

local core = exports.core

---@param match HopOutMatch
---@param victimSource Source
---@param killerSource Source?
function Hopouts.registerKill(match, victimSource, killerSource)
    local victim = match.players[victimSource]

    if not victim or not victim.alive then
        return
    end

    victim.alive = false
    victim.deaths += 1

    local killer = killerSource and match.players[killerSource] or nil

    if killer and killer ~= victim then
        if killer.side == victim.side then
            killer.kills -= 1
        else
            killer.kills += 1
            killer.roundKills += 1
        end
    end

    Hopouts.broadcast(match, 'hopouts:client:kill', {
        victim = { userId = victim.userId, username = victim.username, side = victim.side },
        killer = killer and { userId = killer.userId, username = killer.username, side = killer.side } or nil,
        teamKill = killer ~= nil and killer.side == victim.side,
    })

    Hopouts.broadcastRoster(match)

    TriggerEvent('hopouts:server:onKill', match.id, victimSource, killerSource)
end

---@param match HopOutMatch
---@param side string
function Hopouts.awardRound(match, side)
    match.scores[side] = (match.scores[side] or 0) + 1
end

---@param match HopOutMatch
---@return string? side
function Hopouts.getMatchWinner(match)
    for index = 1, #match.sides do
        local side = match.sides[index]

        if (match.scores[side] or 0) >= match.roundsToWin then
            return side
        end
    end

    return nil
end

---@param match HopOutMatch
---@return table?
function Hopouts.getRoundMvp(match)
    local best

    for _, player in pairs(match.players) do
        if player.roundKills > 0 or player.damage > 0 then
            if not best
                or player.roundKills > best.roundKills
                or (player.roundKills == best.roundKills and player.damage > best.damage)
            then
                best = player
            end
        end
    end

    if not best then
        return nil
    end

    return {
        userId = best.userId,
        username = best.username,
        side = best.side,
        kills = best.roundKills,
        damage = best.damage,
    }
end

---@param match HopOutMatch
function Hopouts.resetRoundStats(match)
    for _, player in pairs(match.players) do
        player.roundKills = 0
    end
end

---@param match HopOutMatch
---@return table[]
function Hopouts.buildScoreboard(match)
    local rows = {}

    local rankedRunning = GetResourceState('ranked') == 'started'

    for _, player in pairs(match.players) do
        local hits = player.hits or 0
        local rank

        if rankedRunning then
            local ok, result = pcall(function()
                return exports.ranked:GetRankName(player.userId)
            end)

            rank = ok and result or nil
        end

        rows[#rows + 1] = {
            userId = player.userId,
            username = player.username,
            side = player.side,
            kills = player.kills,
            deaths = player.deaths,
            assists = player.assists,
            damage = player.damage,
            -- Share of this player's hits on enemies that landed on the head.
            headshotPercent = hits > 0 and math.floor((player.headshots or 0) * 100 / hits + 0.5) or 0,
            ping = player.connected and GetPlayerPing(player.source --[[@as string]]) or 0,
            rank = rank,
            alive = player.alive,
            connected = player.connected,
        }
    end

    table.sort(rows, function(a, b)
        if a.kills ~= b.kills then
            return a.kills > b.kills
        end

        return a.damage > b.damage
    end)

    return rows
end

---@param match HopOutMatch
---@param winningSide string?
function Hopouts.pushScoreboard(match, winningSide)
    local rows = Hopouts.buildScoreboard(match)

    for playerSource, player in pairs(match.players) do
        TriggerClientEvent('hopouts:client:scoreboard', playerSource, {
            rows = rows,
            scores = match.scores,
            sides = match.sides,
            colours = Hopouts.getSideColours(match),
            round = match.round,
            roundsToWin = match.roundsToWin,
            isWinner = winningSide ~= nil and player.side == winningSide,
            winningSide = winningSide,
        })
    end
end

---The hold-TAB scoreboard: the same rows the round end shows, for the asking
---player only, marked live so the client shows it without taking focus.
---Rate-limited per player to the client's one-a-second refresh.
local lastScoreboardRequest = {}

RegisterNetEvent('hopouts:server:requestScoreboard', function()
    local source = source --[[@as Source]]
    local now = GetGameTimer()

    if (lastScoreboardRequest[source] or 0) + 800 > now then
        return
    end

    lastScoreboardRequest[source] = now

    local match = Hopouts.getMatchForPlayer(source)

    if not match or (match.state ~= 'live' and match.state ~= 'preround') then
        return
    end

    TriggerClientEvent('hopouts:client:scoreboard', source, {
        rows = Hopouts.buildScoreboard(match),
        scores = match.scores,
        sides = match.sides,
        round = match.round,
        roundsToWin = match.roundsToWin,
        live = true,
    })
end)

AddEventHandler('playerDropped', function()
    lastScoreboardRequest[source] = nil
end)

local MAX_REPORTED_DAMAGE = 200

---GTA's ped component index for the head, as weaponDamageEvent reports it.
local HEAD_COMPONENT = 20

---Damage and headshots, counted on the server from the game's own hit
---events. Nothing on the client ever called reportDamage below, so DMG and
---HS% sat at 0 on every scoreboard; this needs no client cooperation, and a
---client cannot inflate it.
AddEventHandler('weaponDamageEvent', function(sender, data)
    if WasEventCanceled() then
        return
    end

    local source = tonumber(sender) --[[@as Source]]
    local match = Hopouts.getMatchForPlayer(source)

    if not match or match.state ~= 'live' then
        return
    end

    local attacker = match.players[source]

    if not attacker or not attacker.alive then
        return
    end

    local target = data.hitGlobalId and NetworkGetEntityFromNetworkId(data.hitGlobalId) or 0

    if target == 0 then
        return
    end

    local victim

    for playerSource, player in pairs(match.players) do
        if GetPlayerPed(playerSource --[[@as string]]) == target then
            victim = player
            break
        end
    end

    -- Enemies only: friendly fire and hits on the dead do not count.
    if not victim or victim == attacker or victim.side == attacker.side or not victim.alive then
        return
    end

    local amount = math.min(math.floor(tonumber(data.weaponDamage) or 0), MAX_REPORTED_DAMAGE)

    if amount <= 0 then
        return
    end

    attacker.damage += amount
    attacker.hits = (attacker.hits or 0) + 1

    if data.hitComponent == HEAD_COMPONENT then
        attacker.headshots = (attacker.headshots or 0) + 1
    end
end)

RegisterNetEvent('hopouts:server:reportDamage', function(targetUserId, amount)
    local source = source --[[@as Source]]
    local match = Hopouts.getMatchForPlayer(source)

    if not match or match.state ~= 'live' then
        return
    end

    local attacker

    for _, player in pairs(match.players) do
        if player.userId == targetUserId then
            attacker = player
            break
        end
    end

    if not attacker or attacker.source == source then
        return
    end

    amount = tonumber(amount)

    if not amount or amount <= 0 then
        return
    end

    attacker.damage += math.min(math.floor(amount), MAX_REPORTED_DAMAGE)
end)

RegisterNetEvent('hopouts:server:reportDeath', function(killerServerId)
    local source = source --[[@as Source]]
    local match = Hopouts.getMatchForPlayer(source)

    if not match or match.state ~= 'live' then
        return
    end

    local killerSource = tonumber(killerServerId)

    if killerSource and not match.players[killerSource] then
        killerSource = nil
    end

    Hopouts.registerKill(match, source, killerSource --[[@as Source?]])
end)

---The career page, leaderboard and podiums all read `user_game_stats`, and
---nothing ever wrote to it: every kill, death and win on this server was
---thrown away when the match ended. Written once per match, at matchend, for
---everyone still in it (a leaver's stats go with them, as a loss for their
---side is already implied by the other side winning).
---@param match HopOutMatch
---@param winningSide string?
function Hopouts.recordStats(match, winningSide)
    local rows = {}

    for _, player in pairs(match.players) do
        if player.userId then
            local won = winningSide ~= nil and player.side == winningSide
            local lost = winningSide ~= nil and player.side ~= winningSide

            rows[#rows + 1] = {
                player.userId,
                'hopouts',
                math.max(0, player.kills or 0),
                math.max(0, player.deaths or 0),
                won and 1 or 0,
                lost and 1 or 0,
            }
        end
    end

    if #rows == 0 then
        return
    end

    -- XP for the match (levels/config/shared.lua prices each). Nothing called
    -- levels' Award, so every player sat at level 1 forever.
    if GetResourceState('levels') == 'started' then
        for _, player in pairs(match.players) do
            if player.connected and GetPlayerName(player.source --[[@as string]]) then
                pcall(function()
                    local levels = exports.levels

                    if (player.kills or 0) > 0 then
                        levels:Award(player.source, 'kills', player.kills)
                    end

                    if (player.headshots or 0) > 0 then
                        levels:Award(player.source, 'headshots', player.headshots)
                    end

                    if winningSide then
                        levels:Award(player.source, player.side == winningSide and 'wins' or 'losses', 1)
                    end
                end)
            end
        end
    end

    CreateThread(function()
        local ok, err = pcall(function()
            for index = 1, #rows do
                MySQL.prepare.await([[
                    INSERT INTO user_game_stats (user_id, category, kills, deaths, wins, losses)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        kills = kills + VALUES(kills),
                        deaths = deaths + VALUES(deaths),
                        wins = wins + VALUES(wins),
                        losses = losses + VALUES(losses)
                ]], rows[index])
            end
        end)

        if not ok then
            lib.print.error(('[hopouts] could not record match stats: %s'):format(err))
        end
    end)
end

---@param match HopOutMatch
---@param winningSide string?
function Hopouts.logResult(match, winningSide)
    core:Log('commands', ('[hopouts] match %s on %s ended %s'):format(
        match.id,
        match.map.id,
        winningSide and ('%s won %s'):format(winningSide, json.encode(match.scores)) or 'with no winner'
    ))
end
