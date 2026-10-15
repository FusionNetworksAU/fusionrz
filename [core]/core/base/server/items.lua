local LibDeflate = require 'modules.deflate'

---@type ItemsLookup
local items = {}

---@type HandItemsLookup
local handItems = {}

local itemsReady = false

---@return boolean
function Core.areItemsReady()
    return itemsReady
end

---@return ItemsLookup
function Core.getAllItems()
    return items
end

---@return HandItemsLookup
function Core.getAllHandItems()
    return handItems
end

---@param itemId string
---@return Item?
function Core.getItem(itemId)
    return items[itemId]
end

---@param category ItemCategory
---@return ItemsLookup
function Core.getItemsByCategory(category)
    ---@type ItemsLookup
    local matches = {}

    for itemId, item in pairs(items) do
        if item.category == category then
            matches[itemId] = item
        end
    end

    return matches
end

---@param ace string
---@return string? itemId
function Core.getItemIdByAce(ace)
    if type(ace) ~= 'string' then
        return nil
    end

    local dotIndex = ace:find('.', 1, true)

    if not dotIndex then
        return nil
    end

    local itemId = ace:sub(dotIndex + 1)
    local item = items[itemId]

    return (item and item.ace == ace) and itemId or nil
end

---Pulls the catalogue from the database and tells every consumer to reseed.
---imports/items.lua listens for core:itemsReady and copies the tables, so a
---refresh has to fire the event even when nothing changed shape.
---@return boolean success
function Core.refreshItems()
    local ok, fetchedItems = pcall(Core.db.getItems)

    if not ok then
        lib.print.error(('[core] item fetch failed: %s'):format(fetchedItems))

        return false
    end

    local handOk, fetchedHandItems = pcall(Core.db.getHandItems)

    if not handOk then
        lib.print.error(('[core] hand item fetch failed: %s'):format(fetchedHandItems))

        return false
    end

    items = fetchedItems --[[@as ItemsLookup]]
    handItems = fetchedHandItems --[[@as HandItemsLookup]]
    itemsReady = true

    TriggerEvent('core:itemsReady')
    TriggerClientEvent('core:itemsReady', -1)

    -- Anyone who loaded before the catalogue arrived has an inventory that
    -- dropped every entry for want of an item to match it against.
    for _, player in pairs(Core.getPlayers()) do
        Core.refreshInventory(player)
        Core.pushInventory(player)
    end

    return true
end

---Removes an item everywhere: the catalogue, every live consumer's lookup and
---every inventory row holding it. Called when an item is retired, which has
---to leave nobody owning a dangling id.
---@param itemId string
---@return boolean removed
function Core.deleteItemById(itemId)
    if not items[itemId] then
        return false
    end

    items[itemId] = nil

    local removedRows = Core.db.removeInventoryItemEverywhere(itemId)

    TriggerEvent('core:onItemDeletedById', itemId)
    TriggerClientEvent('core:onItemDeletedById', -1, itemId)

    Core.log('items', ('item %s deleted, %s inventory rows removed'):format(itemId, removedRows))

    for _, player in pairs(Core.getPlayers()) do
        Core.refreshInventory(player)
    end

    return true
end

---The whole catalogue in one reply, deflate-compressed.
---
---Uncompressed this was a single net event carrying every item row and every
---hand item, and an event over the size limit is dropped on the floor rather
---than rejected -- which the client sees only as the callback timing out
---after five minutes. The catalogue is mostly repeated keys, so it
---compresses hard, and core/main.lua unpacks it on the other side.
---
---Anything json cannot write (hand items keep their offset and rotation as
---vec3) made json.encode throw inside the handler, so no reply was ever sent
---and every client sat out the full timeout. The payload is now a plain copy,
---built under pcall, and a failure is logged here and answered with nil so the
---client retries instead of waiting.

---@param value any
---@return any
local function plain(value)
    local kind = type(value)

    if kind == 'vector3' or kind == 'vector4' or kind == 'vector2' then
        return { x = value.x, y = value.y, z = value.z, w = value.w }
    end

    if kind == 'table' then
        local copy = {}

        for key, inner in pairs(value) do
            copy[key] = plain(inner)
        end

        return copy
    end

    if kind == 'function' or kind == 'userdata' or kind == 'thread' then
        return nil
    end

    return value
end

---@type string? the last compressed catalogue, rebuilt only after a refresh
local cachedPayload = nil

AddEventHandler('core:itemsReady', function()
    cachedPayload = nil
end)

lib.callback.register('core:server:getItems', function()
    if not itemsReady then
        return nil
    end

    if cachedPayload then
        return cachedPayload
    end

    local ok, result = pcall(function()
        return LibDeflate:CompressDeflate(json.encode({
            items = plain(items),
            handItems = plain(handItems),
        }))
    end)

    if not ok or type(result) ~= 'string' then
        lib.print.error(('[core] could not send the item catalogue: %s'):format(result))

        return nil
    end

    -- Every client asks at once after a refresh; compress once, not per player.
    cachedPayload = result

    return result
end)

Core.onReady(function()
    Core.onDatabaseReady(function()
        CreateThread(function()
            while not Core.refreshItems() do
                Wait(5000)
            end
        end)
    end)
end)

exports('AreItemsReady', Core.areItemsReady)
exports('GetAllItems', Core.getAllItems)
exports('GetAllHandItems', Core.getAllHandItems)
exports('GetItem', Core.getItem)
exports('GetItemsByCategory', Core.getItemsByCategory)
exports('GetItemIdByAce', Core.getItemIdByAce)
exports('RefreshItems', Core.refreshItems)
exports('DeleteItemById', Core.deleteItemById)
