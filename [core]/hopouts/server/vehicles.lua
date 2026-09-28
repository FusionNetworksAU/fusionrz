---Round vehicles.
---
---Spawned server-side so they exist in the match bucket for everyone at
---once, and deleted at round end so a wreck from the last round is never
---cover in the next one.

Hopouts = Hopouts or {}

---@param model string
---@param coords vector4
---@param bucket integer
---@return integer? entity
---@type table<string, true>
local warnedModels = {}

local function spawn(model, coords, bucket)
    local entity = CreateVehicle(joaat(model), coords.x, coords.y, coords.z, coords.w or 0.0, true, true)

    -- CreateVehicle returns a non-zero handle even for a model the server has
    -- never heard of, and the next native on that handle throws "Tried to
    -- access invalid entity". DoesEntityExist is the only reliable check.
    -- Warned once per model so a missing vehicle pack is one line, not one
    -- line per spawn point per round.
    if entity == 0 or not DoesEntityExist(entity) then
        if not warnedModels[model] then
            warnedModels[model] = true

            lib.print.warn(('[hopouts] vehicle model "%s" is not streamed on this server; skipping its spawns.'):format(model))
        end

        return nil
    end

    SetEntityRoutingBucket(entity, bucket)

    return entity
end

---Cars each team gets at its spawn, and how far apart they are parked.
local CARS_PER_TEAM = 3
local CAR_SPACING = 5.0

---A centre car further than this from the map centre is a stale coordinate
---(Mirror Park's still pointed at the old DM Arena, in the sky), not a spot
---on this map, and is skipped.
local MAX_CENTRE_CAR_DISTANCE = 600.0

---Where one team's cars go. A map can list them per side
---(`teamVehicles = { A = { vec4, ... }, B = { ... } }`); without that, the
---side's single `vehicleSpawns` spot becomes a row of CARS_PER_TEAM cars
---parked side by side, all facing the same way.
---@param map HopOutMap
---@param side string
---@param index integer the side's position in map order (1 = A, 2 = B)
---@return vector4[]
local function teamCarSpots(map, side, index)
    local listed = map.teamVehicles and map.teamVehicles[side]

    if listed and #listed > 0 then
        return listed
    end

    local base = map.vehicleSpawns and map.vehicleSpawns[index]

    if not base then
        return {}
    end

    local heading = math.rad(base.w or 0.0)
    -- Sideways relative to the way the cars face.
    local rightX, rightY = math.cos(heading), math.sin(heading)
    local spots = {}

    for slot = 1, CARS_PER_TEAM do
        local offset = (slot - (CARS_PER_TEAM + 1) / 2) * CAR_SPACING

        spots[slot] = vec4(base.x + rightX * offset, base.y + rightY * offset, base.z, base.w or 0.0)
    end

    return spots
end

---@param match HopOutMatch
function Hopouts.spawnVehicles(match)
    Hopouts.despawnVehicles(match)

    local map = match.map
    local config = Hopouts.sharedConfig
    local spawned = {}

    -- Map sides in a fixed order (A, B, ...), so each physical spawn area gets
    -- its own row of cars whichever team is standing there after half-time.
    local sides = {}

    for side in pairs(map.sides or {}) do
        sides[#sides + 1] = side
    end

    table.sort(sides)

    for index, side in ipairs(sides) do
        for slot, spot in ipairs(teamCarSpots(map, side, index)) do
            local model = config.vehicleModels[slot] or config.vehicleModels[1]
            local entity = spawn(model, spot, match.bucket)

            if entity then
                spawned[#spawned + 1] = entity
            end
        end
    end

    local centre = map.centreVehicleSpawn

    if centre and map.centre
        and #(vec2(centre.x, centre.y) - vec2(map.centre.x, map.centre.y)) > MAX_CENTRE_CAR_DISTANCE then
        centre = nil
    end

    if centre then
        local entity = spawn(config.centerVehicleModel, centre, match.bucket)

        if entity then
            spawned[#spawned + 1] = entity
        end
    end

    -- On the match, not match.data: setState wipes data on every
    -- transition, and preround spawns these while live has to still see them.
    match.vehicles = spawned
end

---Every vehicle in the match's routing bucket. The bucket belongs to the match
---alone, so anything in it is a round car -- including ones the tracked list
---lost (a car the game re-created after it changed owners, a wreck, one a
---client spawned), which is why cars used to pile up round after round.
---@param bucket integer
---@return integer[]
local function vehiclesInBucket(bucket)
    local found = {}

    for _, entity in ipairs(GetAllVehicles()) do
        if DoesEntityExist(entity) and GetEntityRoutingBucket(entity) == bucket then
            found[#found + 1] = entity
        end
    end

    return found
end

---@param entities integer[]
local function deleteAll(entities)
    for index = 1, #entities do
        local entity = entities[index]

        if DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
    end
end

---@param match HopOutMatch
function Hopouts.despawnVehicles(match)
    if match.vehicles then
        deleteAll(match.vehicles)
        match.vehicles = nil
    end

    if not match.bucket then
        return
    end

    deleteAll(vehiclesInBucket(match.bucket))

    -- A deletion the owning client had not processed yet (someone was still
    -- driving it) can leave the car standing for a moment; sweep once more.
    local bucket = match.bucket

    SetTimeout(1000, function()
        -- Only if the next round has not already put its own cars there.
        if match.vehicles == nil then
            deleteAll(vehiclesInBucket(bucket))
        end
    end)
end
