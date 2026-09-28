---Sides, colours and the halftime swap.
---
---"Side" is the fixed slot in the map (A/B); the colour is what the player
---sees. Swapping sides at halftime therefore moves the spawns, not the
---colours, which is why the scoreboard keeps reading the same team as the
---same team all match.

Hopouts = Hopouts or {}

local core = exports.core

local COLOUR_ORDER ={ 'Red', 'Blue', 'Green', 'Yellow', 'Violet', 'Cyan', 'Orange', 'Pink', 'White', 'Brown' }

---@param match HopOutMatch
---@return table<string, table> side -> colour definition from config/shared.lua
function Hopouts.getSideColours(match)
    local colours = {}

    for index = 1, #match.sides do
        local name = COLOUR_ORDER[index] or 'White'

        colours[match.sides[index]] = {
            name = name,
            hex = Hopouts.sharedConfig.colors[name].hex,
            blip = Hopouts.sharedConfig.colors[name].blip,
            hud = Hopouts.sharedConfig.colors[name].hud,
            vehicle = Hopouts.sharedConfig.colors[name].vehicle,
        }
    end

    return colours
end

---The emptiest side, so an uneven join count spreads instead of stacking.
---@param match HopOutMatch
---@return string
function Hopouts.pickSide(match)
    local best, bestCount

    for index = 1, #match.sides do
        local side = match.sides[index]
        local count = #Hopouts.getPlayers(match, side)

        if not bestCount or count < bestCount then
            best, bestCount = side, count
        end
    end

    return best or match.sides[1]
end

---The spawn a player uses this round. Slots are per side, so a player keeps
---the same relative position every round and the swap below is the only
---thing that moves them.
---@param match HopOutMatch
---@param player HopOutPlayer
---@return vector4?
function Hopouts.getSpawn(match, player)
    local side = Hopouts.getEffectiveSide(match, player.side)
    local spawns = match.map.sides[side]

    if not spawns then
        return nil
    end

    local spawn = spawns[player.slot] or spawns[1]

    return spawn and spawn.coords or nil
end

---Which physical side of the map a logical side is standing on right now.
---@param match HopOutMatch
---@param side string
---@return string
function Hopouts.getEffectiveSide(match, side)
    if not match.swapped or #match.sides ~= 2 then
        return side
    end

    return side == match.sides[1] and match.sides[2] or match.sides[1]
end

---@param match HopOutMatch
function Hopouts.swapSides(match)
    match.swapped = not match.swapped

    Hopouts.broadcast(match, 'hopouts:client:sidesSwapped', match.swapped)
end

---@param match HopOutMatch
function Hopouts.broadcastRoster(match)
    local roster = {}

    for index = 1, #match.sides do
        local side = match.sides[index]
        local members = {}

        for _, player in pairs(Hopouts.getPlayers(match, side)) do
            -- The teammate list renders the Discord avatar beside the name, so
            -- the roster has to carry it: the match player is hopouts' own
            -- record and never held one.
            local corePlayer = core:GetPlayer(player.source)

            members[#members + 1] = {
                userId = player.userId,
                username = player.username,
                slot = player.slot,
                alive = player.alive,
                source = player.source,
                avatar = corePlayer and corePlayer.avatar or nil,
            }
        end

        table.sort(members, function(a, b) return a.slot < b.slot end)

        roster[side] = members
    end

    Hopouts.broadcast(match, 'hopouts:client:roster', {
        sides = match.sides,
        colours = Hopouts.getSideColours(match),
        roster = roster,
        scores = match.scores,
        round = match.round,
        swapped = match.swapped,
    })
end

---@param match HopOutMatch
---@param side string
---@return boolean
function Hopouts.isSideWiped(match, side)
    local players = Hopouts.getPlayers(match, side)

    if #players == 0 then
        return true
    end

    for index = 1, #players do
        if players[index].alive then
            return false
        end
    end

    return true
end

---@param match HopOutMatch
---@return string? side the only side left standing, nil while more than one is
function Hopouts.getLastSideStanding(match)
    local survivor

    for index = 1, #match.sides do
        local side = match.sides[index]

        if not Hopouts.isSideWiped(match, side) then
            if survivor then
                return nil
            end

            survivor = side
        end
    end

    return survivor
end
