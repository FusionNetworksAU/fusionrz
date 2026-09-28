local defaultLocations = require 'data.locations'
local carFightsLocations = require 'data.car_fights_locations'
local jungleRedzoneLocations = require 'data.jungle_redzone_locations'

---@type table<GameMode, table>
local pools = {
    car_fights_ffa = carFightsLocations,
    jungle_redzone = jungleRedzoneLocations,
}

---@param mode GameMode
---@return table
local function get(mode)
    return pools[mode] or defaultLocations
end

return {
    get = get,
}
