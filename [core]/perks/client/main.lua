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
