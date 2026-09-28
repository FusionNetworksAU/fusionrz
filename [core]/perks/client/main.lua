---Stub perks resource.
---
---`gamemodes/client/main.lua` calls perks:setHealthDisabled / setArmorDisabled
---/ setReviveDisabled on every mode enter and exit. The real perks resource is
---not part of this base, and a missing export throws straight out of the enter
---path, which stops the player entering a gamemode at all.
---
---So this holds the flags and exposes them, and does nothing else. Anything
---that wants to act on them can read them; when the real resource arrives,
---delete this folder.

local state = {
    healthDisabled = false,
    armorDisabled = false,
    reviveDisabled = false,
}

---@param key string
---@return fun(value: boolean)
local function setter(key)
    return function(value)
        state[key] = value == true

        -- So other resources can react without depending on this stub's API.
        TriggerEvent('perks:client:stateChanged', key, state[key])
    end
end

exports('setHealthDisabled', setter('healthDisabled'))
exports('setArmorDisabled', setter('armorDisabled'))
exports('setReviveDisabled', setter('reviveDisabled'))

exports('isHealthDisabled', function() return state.healthDisabled end)
exports('isArmorDisabled', function() return state.armorDisabled end)
exports('isReviveDisabled', function() return state.reviveDisabled end)

exports('getState', function()
    return { healthDisabled = state.healthDisabled, armorDisabled = state.armorDisabled, reviveDisabled = state.reviveDisabled }
end)
