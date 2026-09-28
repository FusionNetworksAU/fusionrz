---Entity creation and ped-task hooks.
---
---entityCreating fires before the entity exists, so refusing it here costs
---nothing on the network. The checks are deliberately narrow: a false
---positive deletes something a gamemode legitimately spawned.

---@type table<integer, true>
local blockedModels = {}

do
    local raw = GetConvar('core:blockedModels', '')

    for model in raw:gmatch('[^,]+') do
        blockedModels[joaat(model:gsub('%s', ''))] = true
    end
end

AddEventHandler('entityCreating', function(entity)
    local owner = NetworkGetEntityOwner(entity)

    -- Server-created entities have no owning player, and a bucket with
    -- strict lockdown has already refused anything a client tried to make.
    if not owner or owner == 0 then
        return
    end

    local model = GetEntityModel(entity)

    if not blockedModels[model] then
        return
    end

    CancelEvent()

    Core.flag(owner, 'entity-model', tostring(model), 'protection_entity')
end)

---Clearing another player's tasks is how most menus ragdoll or freeze
---someone else. A player clearing their own is ordinary.
AddEventHandler('clearPedTasksEvent', function(sender, data)
    local source = tonumber(sender) --[[@as Source]]
    local targetPed = NetworkGetEntityFromNetworkId(data.pedId)
    local ownPed = GetPlayerPed(source --[[@as string]])

    if targetPed == ownPed then
        return
    end

    CancelEvent()

    Core.flag(source, 'clear-ped-tasks', ('targeted net id %s'):format(data.pedId))
end)

AddEventHandler('giveWeaponEvent', function(sender)
    CancelEvent()

    Core.flag(tonumber(sender) --[[@as Source]], 'give-weapon', 'client tried to grant itself a weapon', 'protection_weapon')
end)

AddEventHandler('removeAllWeaponsEvent', function(sender)
    CancelEvent()

    Core.flag(tonumber(sender) --[[@as Source]], 'remove-all-weapons', 'client tried to strip weapons')
end)
