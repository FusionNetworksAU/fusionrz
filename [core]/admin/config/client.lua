local config = require '@core.config.client'

return {
    teleportLocations = {
        {
            coords = vec4(-270.4612, -1038.8031, 1030.5165, 180.6886),
            label = 'Admin Island'
        },
        {
            coords = config.spawnLocation,
            label = 'Spawn'
        }
    }
}