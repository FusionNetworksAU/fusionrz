---Gamemode lifecycle: previews, instances, spawns, scoring and round end.
---
---One instance per portal id, kept alive while anyone is in it, the way a
---persistent FFA server works: you walk into the portal, you join whatever
---round is already running. Each instance owns a routing bucket so two modes
---running at once cannot see or shoot each other.

local core = exports.core

local RESPAWN_DELAY_MSEC = 3000
local PODIUM_MSEC = 12000
local PORTAL_COUNT_INTERVAL_MSEC = 5000

---@type table<string, GamemodeInstance>
local instances = {}

---@type table<Source, string> source -> instance id
local playerInstance = {}

---Source -> { portalId, map }. The map is remembered because the preview camera
---is placed on it before any instance exists; without this the preview rolled
---one arena and createInstance then rolled a different one, so you previewed
---one map and spawned into another.
---@type table<Source, { portalId: string, map: GamemodeMap }>
local previewing = {}

-- ------------------------------------------------------------- helpers ----

---@param source Source
---@return GamemodeInstance?
local function instanceOf(source)
    local id = playerInstance[source]

    return id and instances[id] or nil
end

---@param instance GamemodeInstance
---@param event string
local function broadcast(instance, event, ...)
    for source in pairs(instance.players) do
        TriggerClientEvent(event, source, ...)
    end
end

---@param instance GamemodeInstance
---@return table[] top three by kills
local function buildTop3(instance)
    local rows = {}

    for source, score in pairs(instance.scores) do
        local player = core:GetPlayer(source)

        rows[#rows + 1] = {
            id = source,
            username = player and player.username or ('Player %d'):format(source),
            avatar = player and player.avatar or nil,
            kills = score.kills,
            deaths = score.deaths,
        }
    end

    table.sort(rows, function(a, b) return a.kills > b.kills end)

    while #rows > 3 do
        rows[#rows] = nil
    end

    return rows
end

---@param instance GamemodeInstance
---@param source Source
function Gamemodes.pushStats(instance, source)
    local handler = Gamemodes.getHandler(instance.def)
    local value, maxValue = handler.getStats(instance, source)

    TriggerClientEvent('gamemodes:statsUpdated', source, value, maxValue)
end

---@param instance GamemodeInstance
local function pushTop3(instance)
    broadcast(instance, 'gamemodes:top3Updated', buildTop3(instance))
end

-- ------------------------------------------------------------ instances ----

---@param portalId string
---@param mode GameMode
---@param map GamemodeMap? the map the player was shown in the preview
---@return GamemodeInstance
local function createInstance(portalId, mode, map)
    local def = assert(Gamemodes.getDefinition(mode), 'no definition for mode ' .. tostring(mode))
    local lease = core:CreateBucket('gamemodes', ('gamemode:%s'):format(portalId))

    local instance = {
        id = portalId,
        mode = mode,
        def = def,
        map = map or Gamemodes.pickMap(mode),
        bucket = lease.id,
        players = {},
        scores = {},
        gungame = {},
        phase = 'live',
        endsAt = GetGameTimer() + def.durationMsec,
        spawnCursor = 0,
    }

    instances[portalId] = instance

    return instance
end

---@param instance GamemodeInstance
local function destroyInstance(instance)
    if not instances[instance.id] then
        return
    end

    instances[instance.id] = nil

    core:DestroyBucket(instance.bucket)
end

---@param instance GamemodeInstance
---@param source Source
---@param returnToSpawn boolean
local function removePlayer(instance, source, returnToSpawn)
    if not instance.players[source] then
        return
    end

    instance.players[source] = nil
    instance.scores[source] = nil
    instance.gungame[source] = nil
    playerInstance[source] = nil

    Gamemodes.getHandler(instance.def).onExit(instance, source)

    if instance.mode == 'car_fights_ffa' then
        Gamemodes.clearCarFights(source)
    end

    -- core/base/server/buckets.lua defines LOBBY_BUCKET as 0. It is a field on
    -- core's internal table rather than an export, so it cannot be read from
    -- here; 0 is the value, not a fallback.
    core:SetPlayerBucket(source, 0)
    TriggerClientEvent('gamemodes:cleanup', source, returnToSpawn)

    if not next(instance.players) then
        destroyInstance(instance)
    end
end

---Exposed so `/gm end` and the handlers can finish a round the same way.
---@param instance GamemodeInstance
function Gamemodes.endMatch(instance)
    if instance.phase ~= 'live' then
        return
    end

    instance.phase = 'ended'

    local top3 = buildTop3(instance)

    broadcast(instance, 'gamemodes:matchEnded', {
        first = top3[1],
        second = top3[2],
        third = top3[3],
    })

    SetTimeout(PODIUM_MSEC, function()
        if instances[instance.id] ~= instance then
            return
        end

        for source in pairs(instance.players) do
            removePlayer(instance, source, true)
        end

        destroyInstance(instance)
    end)
end

-- -------------------------------------------------------------- joining ----

lib.callback.register('gamemodes:server:enterPreview', function(source, instanceIdOrMode)
    local mode = Gamemodes.resolveMode(instanceIdOrMode)

    if not mode then
        return nil, ('%s is not set up on this server yet.'):format(tostring(instanceIdOrMode))
    end

    local portalId = type(instanceIdOrMode) == 'string' and instanceIdOrMode or mode
    local instance = instances[portalId]

    -- Preview the map the running round is on, not a fresh roll, or the
    -- player previews one arena and spawns into another.
    local map = instance and instance.map or Gamemodes.pickMap(mode)

    previewing[source] = { portalId = portalId, map = map }

    return {
        mode = mode,
        instanceId = portalId,
        coords = map.preview,
        isCayoIsland = map.isCayoIsland == true,
    }
end)

RegisterNetEvent('gamemodes:server:exitPreview', function()
    previewing[source] = nil
end)

lib.callback.register('gamemodes:server:enterMode', function(source, portalId)
    local mode = Gamemodes.resolveMode(portalId)

    if not mode then
        return nil, 'That gamemode is not available.'
    end

    if playerInstance[source] then
        return nil, 'You are already in a gamemode.'
    end

    local instance = instances[portalId]

    if instance and instance.phase ~= 'live' then
        return nil, 'That round is finishing, try again in a moment.'
    end

    local preview = previewing[source]

    if not instance then
        -- Carry the previewed map across so the arena you were just looking at
        -- is the one you spawn into.
        instance = createInstance(portalId, mode, preview and preview.map or nil)
    end

    previewing[source] = nil

    instance.players[source] = true
    instance.scores[source] = { kills = 0, deaths = 0 }
    playerInstance[source] = instance.id

    core:SetPlayerBucket(source, instance.bucket)

    local spawn = Gamemodes.pickSpawn(instance, source)
    local clientMetadata = Gamemodes.getHandler(instance.def).onEnter(instance, source)

    if GetConvarInt('gamemodes_debug', 0) == 1 then
        print(('[gamemodes] %s entering %s: mode=%s map=%s spawn=%.2f %.2f %.2f'):format(
            GetPlayerName(source) or source, portalId, mode, instance.map.id, spawn.x, spawn.y, spawn.z))
    end

    local vehicleNetId

    if mode == 'car_fights_ffa' then
        vehicleNetId = Gamemodes.spawnCarFightsVehicle(source, spawn)
    end

    local value, maxValue = Gamemodes.getHandler(instance.def).getStats(instance, source)

    pushTop3(instance)

    ---@type EnterGameData
    return {
        mode = mode,
        spawnCoords = spawn,
        isCayoIsland = instance.map.isCayoIsland == true,
        gameEndTime = instance.endsAt,
        gameEndServerNow = GetGameTimer(),
        metadata = clientMetadata,
        vehicleNetId = vehicleNetId,
        statsValue = value,
        statsMaxValue = maxValue,
        top3 = buildTop3(instance),
    }
end)

-- --------------------------------------------------------------- deaths ----

---How long a hit still counts as "who killed you" when the game's own killer
---report comes back empty (a kill from a car, a bleed-out, a burning wreck).
local LAST_HIT_WINDOW_MSEC = 8000

---GTA's ped component index for the head, as weaponDamageEvent reports it.
local HEAD_COMPONENT = 20

---One death can be reported more than once (baseevents plus a respawn race);
---anything inside this window after the last one is the same death.
local DUPLICATE_DEATH_MSEC = 1500

---@type table<Source, { attacker: Source, weapon: integer, headshot: boolean, at: integer }>
local lastHit = {}

---@type table<Source, integer>
local lastDeathAt = {}

-- The last player to hit each gamemode player, straight from the game's hit
-- events. baseevents only knows the killer when the killing blow came from a
-- ped; for anything else it reported -1, which scored no kill and put
-- "Player -1" in the kill feed.
AddEventHandler('weaponDamageEvent', function(sender, data)
    local attacker = tonumber(sender)
    local target = data.hitGlobalId and NetworkGetEntityFromNetworkId(data.hitGlobalId) or 0

    if not attacker or target == 0 or not instanceOf(attacker) then
        return
    end

    for victim in pairs(instances[playerInstance[attacker]].players) do
        if victim ~= attacker and GetPlayerPed(victim --[[@as string]]) == target then
            lastHit[victim] = {
                attacker = attacker,
                weapon = data.weaponType,
                headshot = data.hitComponent == HEAD_COMPONENT,
                at = GetGameTimer(),
            }

            return
        end
    end
end)

---@param victim Source
---@param killer Source?
---@param weaponHash number?
local function handleDeath(victim, killer, weaponHash)
    local instance = instanceOf(victim)

    if not instance or instance.phase ~= 'live' then
        return
    end

    local now = GetGameTimer()

    if lastDeathAt[victim] and now - lastDeathAt[victim] < DUPLICATE_DEATH_MSEC then
        return
    end

    lastDeathAt[victim] = now

    local victimScore = instance.scores[victim]

    if victimScore then
        victimScore.deaths += 1
    end

    -- baseevents sends -1 for "not a player"; that is no killer, not player -1.
    if not killer or killer <= 0 or killer == victim or not instance.players[killer] then
        killer = nil
    end

    local hit = lastHit[victim]
    lastHit[victim] = nil

    local recentHit = hit and now - hit.at <= LAST_HIT_WINDOW_MSEC and instance.players[hit.attacker] and hit or nil

    if not killer and recentHit then
        killer = recentHit.attacker
    end

    if recentHit and recentHit.attacker == killer then
        weaponHash = (weaponHash and weaponHash ~= 0) and weaponHash or recentHit.weapon
    end

    local isHeadshot = recentHit ~= nil and recentHit.attacker == killer and recentHit.headshot

    local killerScore = killer and instance.scores[killer]

    if killerScore then
        killerScore.kills += 1
    end

    local killerPlayer = killer and core:GetPlayer(killer)
    local victimPlayer = core:GetPlayer(victim)
    local meleeHash = instance.def.meleeName and joaat(instance.def.meleeName) or nil

    broadcast(instance, 'gamemodes:playerKilled', {
        isHeadshot = isHeadshot == true,
        -- 'suicide' is how the feed draws a death with nobody to credit (it
        -- shows the victim alone). Anything else needs a killer, so an
        -- uncredited death sent as 'unknown' never showed at all. The client
        -- turns weaponHash into the icon group.
        weaponType = killer and 'weapon' or 'suicide',
        weaponHash = weaponHash,
        killerSrc = killer,
        victimSrc = victim,
        killer = killer and {
            id = killer,
            username = killerPlayer and killerPlayer.username or ('Player %d'):format(killer),
        } or nil,
        victim = {
            id = victim,
            username = victimPlayer and victimPlayer.username or ('Player %d'):format(victim),
        },
    })

    -- Hashes arrive signed from baseevents and unsigned from the hit event;
    -- compare them as unsigned 32-bit so a melee kill is always recognised.
    local isMelee = weaponHash ~= nil and meleeHash ~= nil
        and (math.floor(weaponHash) % 4294967296) == (math.floor(meleeHash) % 4294967296)

    Gamemodes.getHandler(instance.def).onKill(instance, killer, victim, isMelee)

    if killer then
        Gamemodes.pushStats(instance, killer)
    end

    pushTop3(instance)

    -- Respawn back into the same round rather than dropping the player out.
    SetTimeout(RESPAWN_DELAY_MSEC, function()
        if instances[instance.id] ~= instance or not instance.players[victim] then
            return
        end

        if instance.phase ~= 'live' then
            return
        end

        local spawn = Gamemodes.pickSpawn(instance, victim)

        -- The client resurrects at the spawn itself: a server-side teleport of
        -- a dead ped is not reliably honoured, and nothing revived it at all.
        -- Its own handler (not core's) so it can set the player on the
        -- ground: random spawns only carry a rough z.
        TriggerClientEvent('gamemodes:client:respawn', victim, spawn)

        Gamemodes.getHandler(instance.def).onRespawn(instance, victim)

        if instance.mode == 'car_fights_ffa' then
            Gamemodes.spawnCarFightsVehicle(victim, spawn)
        end

        Gamemodes.pushStats(instance, victim)
    end)
end

-- These arrive from the client, so they have to be registered as net events in
-- this resource. With a plain AddEventHandler the server logged
-- "event baseevents:onPlayerDied was not safe for net" and the handler never
-- ran, which meant no kills were scored and nobody ever respawned.
RegisterNetEvent('baseevents:onPlayerKilled', function(killedBy, data)
    handleDeath(source, tonumber(killedBy), data and data.weaponhash or nil)
end)

RegisterNetEvent('baseevents:onPlayerDied', function()
    handleDeath(source, nil, nil)
end)

RegisterNetEvent('baseevents:onPlayerWasted', function()
    handleDeath(source, nil, nil)
end)

-- ---------------------------------------------------------------- votes ----

lib.callback.register('gamemodes:server:submitMapVote', function(source, mapId)
    local instance = instanceOf(source)

    if not instance then
        return false
    end

    instance.votes = instance.votes or {}
    instance.votes[source] = mapId

    local tally = {}

    for _, id in pairs(instance.votes) do
        tally[id] = (tally[id] or 0) + 1
    end

    broadcast(instance, 'gamemodes:voteUpdated', tally)

    return true
end)

-- -------------------------------------------------------- portal counts ----

---The menu shows a live player count under each gamemode card.
local function pushPortalCounts()
    local counts = {}

    for portalId, instance in pairs(instances) do
        local total = 0

        for _ in pairs(instance.players) do
            total += 1
        end

        counts[portalId] = { playerCount = total }
    end

    TriggerClientEvent('gamemodes:client:portalCounts', -1, counts)
end

CreateThread(function()
    while true do
        Wait(PORTAL_COUNT_INTERVAL_MSEC)
        pushPortalCounts()
    end
end)

-- -------------------------------------------------------- round expiry ----

CreateThread(function()
    while true do
        Wait(1000)

        local now = GetGameTimer()

        for _, instance in pairs(instances) do
            if instance.phase == 'live' and now >= instance.endsAt then
                Gamemodes.endMatch(instance)
            end
        end
    end
end)

-- -------------------------------------------------------------- leaving ----

AddEventHandler('playerDropped', function()
    local instance = instanceOf(source)

    previewing[source] = nil
    lastHit[source] = nil
    lastDeathAt[source] = nil

    if instance then
        removePlayer(instance, source, false)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    for _, instance in pairs(instances) do
        for playerSource in pairs(instance.players) do
            removePlayer(instance, playerSource, true)
        end
    end
end)

exports('getInstances', function() return instances end)
exports('getPlayerInstance', function(source) return playerInstance[source] end)
