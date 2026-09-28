---Compatibility shims.
---
---`gamemodes/client/main.lua` calls these five on every mode enter and exit.
---misc ships the configs for this behaviour (hitmarkers/, killeffects/, ...)
---but not the client implementations, so the exports do not exist and a
---missing export throws straight out of the enter path.
---
---These hold the flag and expose it. They deliberately do NOT invent the
---behaviour -- each note below says what the real implementation owes the
---caller. Delete this file when those land.

local state = {
    cayoPerico = false,
    blindFiringDisabled = false,
    canCrouch = false,
    damageTextVisible = false,
    recoil = true,
}

---@param key string
---@return fun(value: any)
local function flag(key)
    return function(value)
        state[key] = value == true
        TriggerEvent('misc:client:compatFlag', key, state[key])
    end
end

---Should stream the Cayo Perico IPLs in and out. Every map in the gamemodes
---pool is mainland, so this is only ever called with `false` today.
exports('ToggleCayoPerico', flag('cayoPerico'))

---Should stop the ped blind-firing from cover.
exports('DisableBlindFiring', flag('blindFiringDisabled'))

---Should enable the scripted crouch.
exports('SetCanCrouch', flag('canCrouch'))

---Should show floating damage numbers on hit.
exports('setDamageTextVisible', flag('damageTextVisible'))

---Should toggle the scripted recoil pattern.
exports('ToggleRecoil', flag('recoil'))

exports('getCompatState', function()
    return {
        cayoPerico = state.cayoPerico,
        blindFiringDisabled = state.blindFiringDisabled,
        canCrouch = state.canCrouch,
        damageTextVisible = state.damageTextVisible,
        recoil = state.recoil,
    }
end)
