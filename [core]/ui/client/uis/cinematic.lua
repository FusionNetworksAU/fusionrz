-- The NUI HUD is hidden while either a cutscene/scripted camera runs or a
-- fullscreen menu (K menu) is open. Tracked separately so one can't unhide the other.
local isCinematicActive = false
local isHiddenByMenu = false

local function pushHudHidden()
    SendNUIMessage({ action = 'setCinematicMode', data = isCinematicActive or isHiddenByMenu })
end

--- Hides the whole NUI HUD while a cutscene or scripted camera runs.
---@param active boolean
local function setCinematicMode(active)
    isCinematicActive = active == true
    pushHudHidden()
end

exports('setCinematicMode', setCinematicMode)

--- Hides the whole NUI HUD while a fullscreen menu is open.
---@param hidden boolean
function SetHudHiddenByMenu(hidden)
    isHiddenByMenu = hidden == true
    pushHudHidden()
end
