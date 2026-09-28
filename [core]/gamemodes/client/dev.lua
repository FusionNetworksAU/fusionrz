---Client half of the solo test commands.
---
---`enterModeImmediate` is already exported by client/main.lua; this just gives
---the server a way to call it, so `/gm <mode>` can skip the menu and the
---preview screen entirely.

if GetConvarInt('gamemodes_debug', 0) ~= 1 then
    return
end

local ui = exports.ui

RegisterNetEvent('gamemodes:dev:enterImmediate', function(target)
    if type(target) ~= 'string' then
        return
    end

    local ok, err = exports.gamemodes:enterModeImmediate(target)

    if not ok then
        ui:notify({ type = 'error', text = err or 'Could not enter that gamemode.', duration = 5000 })
    end
end)
