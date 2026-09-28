---Compatibility shims.
---
---The hopouts-style gamemodes borrow client APIs from hopouts: the hotbar
---item keybinds (which raise hopouts:itemBindPressed) and the damage modifier
---toggle. SetupDamageModifiers is still a shim; it is fire-and-forget at its
---one call site in `gamemodes/client/main.lua`.

local damageModifiersActive = false

---Should install (false) or restore (true) hopouts' scripted damage scaling.
---`false` means "hopouts rules on", which is why the gamemode calls it with
---false on enter and true on exit.
---@param restoreDefaults boolean
exports('SetupDamageModifiers', function(restoreDefaults)
    damageModifiersActive = restoreDefaults ~= true

    TriggerEvent('hopouts:client:damageModifiersChanged', damageModifiersActive)
end)

-- ------------------------------------------------------- item keybinds ----

---The hotbar keys. `item` is the name the hotbar labels it with (what
---GetItemKeybindKey is asked for); `event` is what gamemodes' handler for
---hopouts:itemBindPressed switches on. The two differ for three of them,
---which is why they are listed rather than derived.
---
---Registered as key mappings, so players can rebind them under
---Settings > Key Bindings > FiveM.
local ITEM_BINDS = {
    { item = 'rifle', event = 'rifle', key = '1', label = 'Primary weapon (press again to holster)' },
    { item = 'pistol', event = 'pistol', key = '2', label = 'Pistol (press again to holster)' },
    { item = 'axe', event = 'melee', key = '3', label = 'Melee (press again to holster)' },
    { item = 'vest', event = 'armor', key = '4', label = 'Use armour' },
    { item = 'medkit', event = 'medkit', key = '5', label = 'Use medkit' },
    { item = 'blunt', event = 'blunt', key = '6', label = 'Use blunt' },
    { item = 'repairkit', event = 'repairkit', key = '7', label = 'Use repair kit' },
    { item = 'smoke', event = 'smokes', key = '8', label = 'Smoke grenade' },
}

---@type table<string, table> hotbar item name -> ox_lib keybind
local keybinds = {}

for index = 1, #ITEM_BINDS do
    local bind = ITEM_BINDS[index]

    keybinds[bind.item] = lib.addKeybind({
        name = ('hopouts_item_%s'):format(bind.item),
        description = ('Hopouts: %s'):format(bind.label),
        defaultKey = bind.key,
        onPressed = function()
            -- gamemodes decides whether a session is live; outside one the
            -- press is simply ignored there.
            TriggerEvent('hopouts:itemBindPressed', bind.event)
        end,
    })
end

---The key currently bound to a hotbar item, e.g. '1' or 'F', so the hotbar
---shows the player's own binding rather than the default.
---@param item string
---@return string?
exports('GetItemKeybindKey', function(item)
    local keybind = keybinds[item]

    return keybind and keybind:getCurrentKey() or nil
end)

---@return boolean
exports('AreDamageModifiersActive', function()
    return damageModifiersActive
end)
