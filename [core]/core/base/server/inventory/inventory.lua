---Cosmetic inventory: what a player owns out of the items catalogue, and
---which of those they have equipped. Nothing here touches ox_inventory, which
---owns physical items; these are entitlements.

---@class PlayerInventory
---@field entries table<integer, InventoryEntry> keyed by entry id
---@field ownedTypeIds table<string, integer> item id -> how many copies
---@field equipped table<ItemCategory, string> category -> equipped item id

---@type table<integer, PlayerInventory> userId -> inventory
local inventories = {}

---@param userId integer
---@return PlayerInventory
local function emptyInventory(userId)
    inventories[userId] = {
        entries = {},
        ownedTypeIds = {},
        equipped = {},
    }

    return inventories[userId]
end

---@param player CorePlayer
---@return PlayerInventory
function Core.refreshInventory(player)
    local inventory = emptyInventory(player.userId)

    local ok, entries = pcall(Core.db.getInventory, player.userId)

    if not ok then
        lib.print.error(('[core] inventory fetch failed for %s: %s'):format(player.userId, entries))

        return inventory
    end

    for index = 1, #entries do
        local entry = entries[index]
        local item = Core.getItem(entry.itemId)

        -- An entry whose item has been retired is skipped rather than
        -- deleted: the catalogue may simply not have loaded yet, and
        -- Core.deleteItemById is what actually removes rows.
        if item then
            inventory.entries[entry.id] = entry
            inventory.ownedTypeIds[entry.itemId] = (inventory.ownedTypeIds[entry.itemId] or 0) + 1

            if entry.equipped then
                inventory.equipped[item.category] = entry.itemId
            end
        end
    end

    return inventory
end

---@param player CorePlayer
---@return PlayerInventory
function Core.getInventory(player)
    return inventories[player.userId] or Core.refreshInventory(player)
end

---The shape the client caches. Sent on load and after every change, and
---handed back out of core:server:createUser as the signup snapshot.
---@param player CorePlayer
---@return table
function Core.buildInventorySnapshot(player)
    local inventory = Core.getInventory(player)

    ---@type string[]
    local typeIds = {}

    for itemId in pairs(inventory.ownedTypeIds) do
        typeIds[#typeIds + 1] = itemId
    end

    return {
        typeIds = typeIds,
        equipped = inventory.equipped,
    }
end

---@param player CorePlayer
---@param affectedTypeIds string[]?
---`core:onInventoryUpdated` is a LOCAL event -- core/main.lua raises it once
---the snapshot has been applied, and consumers listen with AddEventHandler.
---Firing it over the network as well meant two things: the "not safe for net"
---warning, since no client registers it as a net event, and consumers being
---told the inventory changed *before* the new snapshot arrived. The affected
---ids ride along with the snapshot instead, and the local event carries them
---from there.
function Core.pushInventory(player, affectedTypeIds)
    TriggerClientEvent('core:client:inventorySnapshot', player.source, Core.buildInventorySnapshot(player), affectedTypeIds)
end

---@param player CorePlayer
---@return string[]
function Core.getUsableTypeIds(player)
    local inventory = Core.getInventory(player)

    ---@type string[]
    local typeIds = {}

    for itemId in pairs(inventory.ownedTypeIds) do
        typeIds[#typeIds + 1] = itemId
    end

    return typeIds
end

---@param player CorePlayer
---@param itemId string
---@return boolean
function Core.ownsItem(player, itemId)
    return Core.getInventory(player).ownedTypeIds[itemId] ~= nil
end

---@param player CorePlayer
---@param itemId string
---@return boolean success
---@return string? error
function Core.giveItem(player, itemId)
    local item = Core.getItem(itemId)

    if not item then
        return false, 'Unknown item.'
    end

    local entryId = Core.db.addInventoryItem(player.userId, itemId)

    if not entryId then
        return false, 'Could not grant item.'
    end

    local inventory = Core.getInventory(player)

    inventory.entries[entryId] = {
        id = entryId,
        itemId = itemId,
        equipped = false,
        acquiredAt = os.time(),
    }

    inventory.ownedTypeIds[itemId] = (inventory.ownedTypeIds[itemId] or 0) + 1

    Core.pushInventory(player, { itemId })
    Core.log('items', ('%s (%s) received %s'):format(player.username, player.userId, itemId))

    return true
end

---@param player CorePlayer
---@param entryId integer
---@return boolean success
---@return string? error
function Core.takeItem(player, entryId)
    local inventory = Core.getInventory(player)
    local entry = inventory.entries[entryId]

    if not entry then
        return false, 'You do not own that.'
    end

    if not Core.db.removeInventoryEntry(entryId, player.userId) then
        return false, 'Could not remove item.'
    end

    inventory.entries[entryId] = nil

    local remaining = (inventory.ownedTypeIds[entry.itemId] or 1) - 1
    inventory.ownedTypeIds[entry.itemId] = remaining > 0 and remaining or nil

    local item = Core.getItem(entry.itemId)

    if item and inventory.equipped[item.category] == entry.itemId and remaining <= 0 then
        inventory.equipped[item.category] = nil
    end

    Core.pushInventory(player, { entry.itemId })

    return true
end

---One equipped item per category. Equipping unequips whatever held the slot,
---which is a two-row write and so goes through a single pass here rather than
---leaving the old row set and letting the next load pick a winner at random.
---@param player CorePlayer
---@param entryId integer
---@return boolean success
---@return string? error
function Core.equipItem(player, entryId)
    local inventory = Core.getInventory(player)
    local entry = inventory.entries[entryId]

    if not entry then
        return false, 'You do not own that.'
    end

    local item = Core.getItem(entry.itemId)

    if not item then
        return false, 'Unknown item.'
    end

    for otherId, other in pairs(inventory.entries) do
        local otherItem = Core.getItem(other.itemId)

        if other.equipped and otherItem and otherItem.category == item.category then
            other.equipped = false

            Core.db.setInventoryEquipped(player.userId, otherId, false)
        end
    end

    entry.equipped = true
    inventory.equipped[item.category] = entry.itemId

    Core.db.setInventoryEquipped(player.userId, entryId, true)

    Core.pushInventory(player, { entry.itemId })

    TriggerEvent('core:server:onItemEquipped', player.source, item.category, entry.itemId)

    return true
end

---@param userId integer
function Core.clearInventoryCache(userId)
    inventories[userId] = nil
end

AddEventHandler('core:server:onPlayerDropped', function(_, userId)
    Core.clearInventoryCache(userId)
end)

exports('GetInventorySnapshot', function(source)
    local player = Core.getPlayer(source)

    return player and Core.buildInventorySnapshot(player) or nil
end)

exports('GetUsableTypeIds', function(source)
    local player = Core.getPlayer(source)

    return player and Core.getUsableTypeIds(player) or {}
end)

exports('OwnsItem', function(source, itemId)
    local player = Core.getPlayer(source)

    return player ~= nil and Core.ownsItem(player, itemId)
end)

---@return boolean success
---@return string? error
exports('GiveItem', function(source, itemId)
    local player = Core.getPlayer(source)

    if not player then
        return false, 'No player loaded.'
    end

    return Core.giveItem(player, itemId)
end)

---@return boolean success
---@return string? error
exports('TakeItem', function(source, entryId)
    local player = Core.getPlayer(source)

    if not player then
        return false, 'No player loaded.'
    end

    return Core.takeItem(player, entryId)
end)
