---@type table<GameMode, boolean>
local hopoutStyle = {
    rifle_ffa = true,
    wingman_ffa = true,
    car_fights_ffa = true,
    deathmatch = true,
    jungle_redzone = true,
}

---@param mode string
---@return boolean
local function isHopoutStyleMode(mode)
    return hopoutStyle[mode] == true
end

return {
    hopoutStyle = hopoutStyle,
    isHopoutStyleMode = isHopoutStyleMode,
}
