---@class HopOutSpawn
---@field coords vector4
---
---@class HopOutMap
---@field id string
---@field label string
---@field image string?
---@field sides table<string, HopOutSpawn[]>
---@field centre vector3
---@field radius number
---@field vehicleSpawns vector4[]?
---@field teamVehicles table<string, vector4[]>?
---@field centreVehicleSpawn vector4?
---@field maxTeamSize integer?
---@field enabled boolean

---Space between players standing in a spawn line.
local SPAWN_GAP = 2.5

---A line of `count` spawns centred on x/y, side by side across `heading`,
---everyone facing the same way. Saves typing five near-identical vec4s per
---side; the client snaps each one onto the ground when it is used.
---@return HopOutSpawn[]
local function spawnRow(x, y, z, heading, count)
    local rad = math.rad(heading)
    local rightX, rightY = math.cos(rad), math.sin(rad)
    local row = {}

    for slot = 1, count do
        local offset = (slot - (count + 1) / 2) * SPAWN_GAP

        row[slot] = { coords = vec4(x + rightX * offset, y + rightY * offset, z, heading) }
    end

    return row
end

---A point `distance` metres behind x/y when facing `heading` -- where that
---side's cars park, so nobody spawns inside one.
---@return vector4
local function behind(x, y, z, heading, distance)
    local rad = math.rad(heading)

    return vec4(x + math.sin(rad) * distance, y - math.cos(rad) * distance, z, heading)
end

---@type table<string, HopOutMap>
return {
    ['mirror'] = {
        id = 'mirror',
        label = 'Mirror Park',
        image = 'mirror.svg',
        enabled = true,

        centre = vec3(1132.3760, -544.4473, 62.4540),
        radius = 120.0,

        sides = {
            A = {
                { coords = vec4(1022.3591, -319.3925, 67.1370, 237.8251) },
                { coords = vec4(1020.8109, -321.9201, 67.1982, 238.7820) },
                { coords = vec4(1019.1317, -324.5414, 67.1015, 237.9336) },
                { coords = vec4(1023.9406, -313.4408, 67.1617, 243.7753) },
                { coords = vec4(1014.7627, -328.7473, 67.1589, 241.9776) },
            },
            B = {
                { coords = vec4(1179.1775, -809.3242, 55.8973, 341.0153) },
                { coords = vec4(1182.0459, -810.4163, 55.8952, 339.4151) },
                { coords = vec4(1185.3600, -811.5609, 55.8509, 340.1521) },
                { coords = vec4(1188.2021, -812.7903, 55.8028, 340.5985) },
                { coords = vec4(1192.0691, -814.0248, 55.7256, 340.8275) },
            },
        },

        vehicleSpawns = {
            vec4(1025.5397, -324.5462, 67.1978, 241.6631),
            vec4(1188.2775, -805.7130, 56.0886, 341.5058),
        },

        centreVehicleSpawn = vec4(-3399.66, 2008.51, 837.33, 0.0),

        maxTeamSize = 5,
    },

    -- Open tarmac between the runways: long sightlines, cover from the cars.
    ['airport'] = {
        id = 'airport',
        label = 'LSIA Tarmac',
        image = 'airport.svg',
        enabled = true,

        centre = vec3(-1336.0, -3044.0, 13.94),
        radius = 150.0,

        sides = {
            A = spawnRow(-1440.0, -2950.0, 13.94, 228.0, 5),
            B = spawnRow(-1230.0, -3140.0, 13.94, 48.0, 5),
        },

        vehicleSpawns = {
            behind(-1440.0, -2950.0, 14.4, 228.0, 10.0),
            behind(-1230.0, -3140.0, 14.4, 48.0, 10.0),
        },

        maxTeamSize = 5,
    },

    -- Sandy Shores airfield: flat desert, the hangars as the only hard cover.
    ['sandy'] = {
        id = 'sandy',
        label = 'Sandy Airfield',
        image = 'sandy.svg',
        enabled = true,

        centre = vec3(1450.0, 3170.0, 40.6),
        radius = 150.0,

        sides = {
            A = spawnRow(1300.0, 3130.0, 40.6, 285.0, 5),
            B = spawnRow(1600.0, 3210.0, 40.6, 105.0, 5),
        },

        vehicleSpawns = {
            behind(1300.0, 3130.0, 41.2, 285.0, 10.0),
            behind(1600.0, 3210.0, 41.2, 105.0, 10.0),
        },

        maxTeamSize = 5,
    },

    -- Downtown: the square, its trees and the streets around it.
    ['legion'] = {
        id = 'legion',
        label = 'Legion Square',
        image = 'legion.svg',
        enabled = true,

        centre = vec3(195.0, -933.0, 30.7),
        radius = 110.0,

        sides = {
            A = spawnRow(150.0, -1030.0, 29.4, 335.0, 5),
            B = spawnRow(245.0, -840.0, 30.2, 152.0, 5),
        },

        vehicleSpawns = {
            behind(150.0, -1030.0, 29.9, 335.0, 10.0),
            behind(245.0, -840.0, 30.7, 152.0, 10.0),
        },

        maxTeamSize = 5,
    },
}
