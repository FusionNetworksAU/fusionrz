--- Hides the whole NUI HUD while a cutscene or scripted camera runs.
---@param active boolean
local function setCinematicMode(active)
    SendNUIMessage({ action = 'setCinematicMode', data = active == true })
end

exports('setCinematicMode', setCinematicMode)
