---Map pool for Jungle Redzone: one map, a ring of spawns around the centre.
---
---The ring is 12m out, eight points, each facing back towards the middle, so
---a respawn lands you looking at the fight rather than at a wall. Spawns are
---handed out round robin (Gamemodes.pickSpawn), which spreads consecutive
---respawns around the ring instead of stacking them.
---
---Every point shares the centre's z. If one of them lands inside a wall or
---under a slope in game, stand where it should be, grab the coords and
---replace that line.

---@type GamemodeMap[]
return {
    {
        id = 'jungle_redzone',
        label = 'Jungle Redzone',
        preview = vec4(397.5665, -1574.2408, 29.3429, 315.3213),
        -- Respawns land on a random point in this circle (Gamemodes.pickSpawn),
        -- away from whoever is alive, facing the middle. The client drops it
        -- onto the ground, so the z only needs to be roughly right. Shrink
        -- the radius if points start landing somewhere you cannot play.
        randomSpawn = {
            centre = vec3(397.5665, -1574.2408, 29.3429),
            radius = 20.0,
            minRadius = 4.0,
        },
        -- First join, and the fallback if a random point is never usable.
        spawns = {
            vec4(397.5665, -1574.2408, 29.3429, 315.3213),
            vec4(409.5665, -1574.2408, 29.3429, 90.0),
            vec4(406.0518, -1565.7555, 29.3429, 135.0),
            vec4(397.5665, -1562.2408, 29.3429, 180.0),
            vec4(389.0812, -1565.7555, 29.3429, 225.0),
            vec4(385.5665, -1574.2408, 29.3429, 270.0),
            vec4(389.0812, -1582.7261, 29.3429, 315.0),
            vec4(397.5665, -1586.2408, 29.3429, 0.0),
            vec4(406.0518, -1582.7261, 29.3429, 45.0),
        },
    },
}
