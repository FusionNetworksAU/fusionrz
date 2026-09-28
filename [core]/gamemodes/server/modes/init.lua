---@alias Source integer
---@alias GameMode 'pistol_ffa'|'mosin_ffa'|'rifle_ffa'|'wingman_ffa'|'car_fights_ffa'|'gungame'|'deathmatch'|'jungle_redzone'

---@class GamemodeDefinition
---@field mode GameMode
---@field label string
---@field handler string      
---@field killTarget integer    
---@field durationMsec integer  
---@field weapons? string[]   
---@field primaryName? string  
---@field meleeName? string     
---@field pistolName? string   

---@class GamemodeInstance
---@field id string
---@field mode GameMode
---@field def GamemodeDefinition
---@field map GamemodeMap
---@field bucket integer
---@field players table<Source, true>
---@field scores table<Source, { kills: integer, deaths: integer }>
---@field gungame table<Source, integer>
---@field phase 'live'|'ended'
---@field endsAt integer
---@field spawnCursor integer
---@field votes? table<Source, string>  map vote, keyed by voter

---@class GamemodeHandler
---@field style 'ffa'|'hopout'
---@field onEnter fun(instance: GamemodeInstance, source: Source): table?
---@field onRespawn fun(instance: GamemodeInstance, source: Source)
---@field onKill fun(instance: GamemodeInstance, killer: Source?, victim: Source?, isMelee: boolean?)
---@field getStats fun(instance: GamemodeInstance, source: Source): integer, integer
---@field onExit fun(instance: GamemodeInstance?, source: Source)

Gamemodes = Gamemodes or {}
Gamemodes.handlers = Gamemodes.handlers or {}

local pools = require 'shared.location_pools'

local LOADOUT = {
    rifle = 'WEAPON_CARBINERIFLE',
    pistol = 'WEAPON_COMBATPISTOL',
    -- With the underscore: that is the game's name for it (hopouts' shared
    -- config uses the same). WEAPON_STONEHATCHET hashes to nothing the game
    -- knows, so the hatchet was never given and key 3 had nothing to equip.
    melee = 'WEAPON_STONE_HATCHET',
}

local MINUTE = 60000

---@type table<GameMode, GamemodeDefinition>
Gamemodes.definitions = {
    pistol_ffa = {
        mode = 'pistol_ffa',
        label = 'Pistol FFA',
        handler = 'ffa',
        killTarget = 30,
        durationMsec = 10 * MINUTE,
        weapons = { 'WEAPON_COMBATPISTOL' },
    },
    mosin_ffa = {
        mode = 'mosin_ffa',
        label = 'Mosin Only FFA',
        handler = 'ffa',
        killTarget = 25,
        durationMsec = 10 * MINUTE,
        weapons = { 'WEAPON_MOSIN' },
    },
    gungame = {
        mode = 'gungame',
        label = 'Gun Game',
        handler = 'gungame',
        killTarget = 12,
        durationMsec = 15 * MINUTE,
    },
    rifle_ffa = {
        mode = 'rifle_ffa',
        label = 'Rifle FFA',
        handler = 'hopout_style',
        killTarget = 30,
        durationMsec = 10 * MINUTE,
        primaryName = LOADOUT.rifle,
        meleeName = LOADOUT.melee,
    },
    wingman_ffa = {
        mode = 'wingman_ffa',
        label = 'Wingman FFA',
        handler = 'hopout_style',
        killTarget = 30,
        durationMsec = 10 * MINUTE,
        primaryName = LOADOUT.pistol,
        meleeName = LOADOUT.melee,
    },
    car_fights_ffa = {
        mode = 'car_fights_ffa',
        label = 'Car Fights',
        handler = 'hopout_style',
        killTarget = 25,
        durationMsec = 10 * MINUTE,
        primaryName = LOADOUT.pistol,
        meleeName = LOADOUT.melee,
    },
    deathmatch = {
        mode = 'deathmatch',
        label = 'Deathmatch',
        handler = 'hopout_style',
        killTarget = 30,
        durationMsec = 10 * MINUTE,
        primaryName = LOADOUT.rifle,
        meleeName = LOADOUT.melee,
    },
    -- Rifle FFA's loadout on its own map (data/jungle_redzone_locations.lua).
    jungle_redzone = {
        mode = 'jungle_redzone',
        label = 'Jungle Redzone',
        handler = 'hopout_style',
        killTarget = 30,
        durationMsec = 10 * MINUTE,
        primaryName = LOADOUT.rifle,
        meleeName = LOADOUT.melee,
    },
}

---@type table<string, GameMode>
Gamemodes.portals = {
    pistol_1 = 'pistol_ffa',
    pistol_2 = 'pistol_ffa',
    mosin_1 = 'mosin_ffa',
    rifle_1 = 'rifle_ffa',
    wingman_1 = 'wingman_ffa',
    wingman_2 = 'wingman_ffa',
    gungame_1 = 'gungame',
    car_fights_1 = 'car_fights_ffa',
    deathmatch_1 = 'deathmatch',
    hopouts_1 = 'rifle_ffa',
    ramps_1v1_1 = 'wingman_ffa',
    jungle_redzone_1 = 'jungle_redzone',
}

---@param instanceIdOrMode string
---@return GameMode?
function Gamemodes.resolveMode(instanceIdOrMode)
    if type(instanceIdOrMode) ~= 'string' then
        return nil
    end

    local portalMode = Gamemodes.portals[instanceIdOrMode]

    if portalMode then
        return portalMode
    end

    return Gamemodes.definitions[instanceIdOrMode] and instanceIdOrMode or nil
end

---@param mode GameMode
---@return GamemodeDefinition?
function Gamemodes.getDefinition(mode)
    return Gamemodes.definitions[mode]
end

---@param def GamemodeDefinition
---@return GamemodeHandler
function Gamemodes.getHandler(def)
    return Gamemodes.handlers[def.handler]
end

---@param mode GameMode
---@return GamemodeMap?
function Gamemodes.pickMap(mode)
    local pool = pools.get(mode)

    if #pool == 0 then
        return nil
    end

    return pool[math.random(#pool)]
end

---Candidate points tried per random respawn; the one furthest from anyone
---alive wins, so you do not come back on top of the player who killed you.
local RANDOM_SPAWN_TRIES = 8

---@param instance GamemodeInstance
---@param exclude Source?
---@return vector3[]
local function livingPositions(instance, exclude)
    local positions = {}

    for playerSource in pairs(instance.players) do
        if playerSource ~= exclude then
            local ped = GetPlayerPed(playerSource --[[@as string]])

            if ped ~= 0 and DoesEntityExist(ped) and GetEntityHealth(ped) > 0 then
                positions[#positions + 1] = GetEntityCoords(ped)
            end
        end
    end

    return positions
end

---A random point inside the map's randomSpawn circle, facing its centre.
---@param area { centre: vector3, radius: number, minRadius: number? }
---@param others vector3[]
---@return vector4
local function randomSpawnIn(area, others)
    local best, bestScore

    for _ = 1, RANDOM_SPAWN_TRIES do
        -- sqrt keeps the points evenly spread over the area, not bunched in
        -- the middle.
        local minRadius = area.minRadius or 0.0
        local distance = minRadius + math.sqrt(math.random()) * (area.radius - minRadius)
        local angle = math.random() * math.pi * 2
        local x = area.centre.x + math.cos(angle) * distance
        local y = area.centre.y + math.sin(angle) * distance

        local nearest = math.huge

        for index = 1, #others do
            local dx, dy = others[index].x - x, others[index].y - y

            nearest = math.min(nearest, math.sqrt(dx * dx + dy * dy))
        end

        if not bestScore or nearest > bestScore then
            -- GTA heading: 0 faces +y, so face the centre with atan2(-dx, dy).
            local heading = math.deg(math.atan(-(area.centre.x - x), area.centre.y - y)) % 360.0

            best = vec4(x, y, area.centre.z, heading)
            bestScore = nearest
        end
    end

    return best
end

---@param instance GamemodeInstance
---@param forSource Source? the player spawning, so they are not avoided
---@return vector4
function Gamemodes.pickSpawn(instance, forSource)
    local area = instance.map.randomSpawn

    if area and area.centre and (area.radius or 0) > 0 then
        return randomSpawnIn(area, livingPositions(instance, forSource))
    end

    local spawns = instance.map.spawns

    instance.spawnCursor = (instance.spawnCursor % #spawns) + 1

    return spawns[instance.spawnCursor]
end
