-- The NUI HUD is hidden while either a cutscene/scripted camera runs or a
-- fullscreen menu (K menu, pause menu) is open. Tracked separately so one can't unhide another.
-- The menus' HUD editor page (Settings > HUD) needs the HUD on screen to drag it around,
-- so a menu stops hiding it while that editor is active (minimap.lua: IsHudEditorActive).
local isCinematicActive = false
local menusHidingHud = {}

local function isHiddenByMenu()
    return next(menusHidingHud) ~= nil and not IsHudEditorActive()
end

function RefreshHudHidden()
    SendNUIMessage({ action = 'setCinematicMode', data = isCinematicActive or isHiddenByMenu() })
end

--- Hides the whole NUI HUD while a cutscene or scripted camera runs.
---@param active boolean
local function setCinematicMode(active)
    isCinematicActive = active == true
    RefreshHudHidden()
end

exports('setCinematicMode', setCinematicMode)

--- Hides the whole NUI HUD (and GTA's native HUD) while a fullscreen menu is open.
---@param menu string
---@param hidden boolean
function SetHudHiddenByMenu(menu, hidden)
    local wasHidden = next(menusHidingHud) ~= nil

    menusHidingHud[menu] = hidden == true or nil
    RefreshHudHidden()

    if wasHidden or not hidden then
        return
    end

    CreateThread(function()
        while next(menusHidingHud) do
            if not IsHudEditorActive() then
                HideHudAndRadarThisFrame()
            end

            Wait(0)
        end
    end)
end
