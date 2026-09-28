-- The NUI HUD is hidden while either a cutscene/scripted camera runs or a
-- fullscreen menu (K menu, pause menu) is open. Tracked separately so one can't unhide another.
local isCinematicActive = false
local menusHidingHud = {}

local function pushHudHidden()
    SendNUIMessage({ action = 'setCinematicMode', data = isCinematicActive or next(menusHidingHud) ~= nil })
end

--- Hides the whole NUI HUD while a cutscene or scripted camera runs.
---@param active boolean
local function setCinematicMode(active)
    isCinematicActive = active == true
    pushHudHidden()
end

exports('setCinematicMode', setCinematicMode)

--- Hides the whole NUI HUD (and GTA's native HUD) while a fullscreen menu is open.
---@param menu string
---@param hidden boolean
function SetHudHiddenByMenu(menu, hidden)
    local wasHidden = next(menusHidingHud) ~= nil

    menusHidingHud[menu] = hidden == true or nil
    pushHudHidden()

    if wasHidden or not hidden then
        return
    end

    CreateThread(function()
        while next(menusHidingHud) do
            HideHudAndRadarThisFrame()
            Wait(0)
        end
    end)
end
