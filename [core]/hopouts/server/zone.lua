Hopouts = Hopouts or {}

-- One big zone: it holds for 20s (the next circle is already on the map, and
-- a countdown shows how long is left), then closes in one slow, steady move
-- to the final circle. Sized to the 150s round in config/shared.lua:
--   0-20 hold | 20-80 close to 10% | 80-150 final circle
local PHASES = {
    { holdMsec = 20000, moveMsec = 60000, radius = 0.10 },
}

local MIN_RADIUS = 12.0

local SPAWN_MARGIN = 30.0

---@param map HopOutMap
---@return { x: number, y: number, z: number, r: number }
local function startingCircle(map)
    local centre = map.centre
    local radius = map.radius or 100.0

    for _, spawns in pairs(map.sides or {}) do
        for index = 1, #spawns do
            local coords = spawns[index].coords
            local distance = #(vec2(coords.x, coords.y) - vec2(centre.x, centre.y))

            radius = math.max(radius, distance + SPAWN_MARGIN)
        end
    end

    return { x = centre.x, y = centre.y, z = centre.z, r = radius }
end

---@param outer { x: number, y: number, z: number, r: number }
---@param radius number
---@return { x: number, y: number, z: number, r: number }
local function circleInside(outer, radius)
    local slack = math.max(0.0, outer.r - radius)
    local angle = math.random() * math.pi * 2
    -- sqrt keeps the pick uniform over the area rather than bunched in the middle.
    local distance = math.sqrt(math.random()) * slack

    return {
        x = outer.x + math.cos(angle) * distance,
        y = outer.y + math.sin(angle) * distance,
        z = outer.z,
        r = radius,
    }
end

---@param match HopOutMatch
---@return table plan
function Hopouts.planZone(match)
    local start = startingCircle(match.map)
    local phases = {}
    local current = start

    for index = 1, #PHASES do
        local phase = PHASES[index]
        local target = circleInside(current, math.max(MIN_RADIUS, start.r * phase.radius))

        phases[index] = {
            holdMsec = phase.holdMsec,
            moveMsec = phase.moveMsec,
            from = current,
            to = target,
        }

        current = target
    end

    return {
        start = start,
        phases = phases,
    }
end

---@param match HopOutMatch
function Hopouts.startZone(match)
    match.zone = Hopouts.planZone(match)

    Hopouts.broadcast(match, 'hopouts:client:zone', match.zone)
end
