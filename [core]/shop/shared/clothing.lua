---Clothing slots.
---
---config/data.lua names the slots the store sells into ('shirts', 'hats',
---...) and maps component/prop names to the numbers the natives use;
---config/debug.lua is what says which of those names a slot covers. This
---turns one into the other, so nothing outside this file has to know that
---'shirts' means components jbib and accs.

-- The manifest loads this folder alphabetically, so shop.lua is not
-- necessarily first. Every file in here creates the table if it is not there.
Shop = Shop or {}

---@class ShopClothingSlot
---@field components integer[]
---@field props integer[]
---@field needsArmType boolean?

---@param category string
---@return ShopClothingSlot
function Shop.resolveClothingSlot(category)
    local entry = require('config.debug').categories[category]

    local slot = { components = {}, props = {} }

    if not entry then
        return slot
    end

    for index = 1, #(entry.components or {}) do
        local id = Shop.data.components[entry.components[index]]

        if id then
            slot.components[#slot.components + 1] = id
        end
    end

    for index = 1, #(entry.props or {}) do
        local id = Shop.data.props[entry.props[index]]

        if id then
            slot.props[#slot.props + 1] = id
        end
    end

    slot.needsArmType = entry.needsArmType == true

    return slot
end

---@param category string?
---@return boolean
function Shop.isClothingCategory(category)
    if not category then
        return false
    end

    for index = 1, #Shop.data.categories do
        if Shop.data.categories[index] == category then
            return true
        end
    end

    return false
end

---The item a slot falls back to when nothing is equipped in it. Without this
---an unequip leaves the last item on the ped, because "wear nothing" is still
---a drawable rather than an absence.
---@param category string
---@return string?
function Shop.getClothingDefault(category)
    local defaults = Shop.data.defaults[category]

    return defaults and defaults[1] or nil
end
