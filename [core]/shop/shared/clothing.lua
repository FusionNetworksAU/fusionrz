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

---@param category string
---@return string?
function Shop.getClothingDefault(category)
    local defaults = Shop.data.defaults[category]

    return defaults and defaults[1] or nil
end

Shop.DEFAULT_CLOTHING_ID = 'default'

local EXTRA_SLOT_COMPONENTS = {
    arms = { 3 },
}

---@param slot string
---@return integer[] components
---@return integer[] props
local function slotParts(slot)
    local resolved = Shop.resolveClothingSlot(slot)
    local components = resolved.components

    if #components == 0 and EXTRA_SLOT_COMPONENTS[slot] then
        components = EXTRA_SLOT_COMPONENTS[slot]
    end

    if resolved.needsArmType then
        components = { table.unpack(components) }
        components[#components + 1] = 3
    end

    return components, resolved.props
end

---@return string[]
function Shop.getClothingSlots()
    local slots = {}

    for index = 1, #Shop.data.categories do
        local slot = Shop.data.categories[index]

        if Shop.data.defaults[slot] then
            slots[#slots + 1] = slot
        end
    end

    return slots
end

---@param slot string
---@return boolean
function Shop.isClothingSlot(slot)
    return type(slot) == 'string' and Shop.data.defaults[slot] ~= nil
end

---@param slot string
---@return { components: table[], props: table[] }
function Shop.getDefaultClothingApply(slot)
    local components, props = slotParts(slot)
    local apply = { components = {}, props = {} }

    for index = 1, #components do
        apply.components[index] = { component_id = components[index], drawable = 0, texture = 0 }
    end

    for index = 1, #props do
        apply.props[index] = { prop_id = props[index], drawable = -1, texture = 0 }
    end

    return apply
end

---@type { components: table<integer, string>, props: table<integer, string> }?
local slotLookup

---@param item table catalogue row (core flattens its `data` onto it)
---@return string?
function Shop.getClothingSlotOf(item)
    local explicit = item.slot or item.clothingCategory or item.clothing_category

    if Shop.isClothingSlot(explicit) then
        return explicit
    end

    if not slotLookup then
        slotLookup = { components = {}, props = {} }

        for _, slot in ipairs(Shop.getClothingSlots()) do
            local resolved = Shop.resolveClothingSlot(slot)
            local components = #resolved.components > 0 and resolved.components or EXTRA_SLOT_COMPONENTS[slot] or {}

            for _, id in ipairs(components) do
                slotLookup.components[id] = slotLookup.components[id] or slot
            end

            for _, id in ipairs(resolved.props) do
                slotLookup.props[id] = slotLookup.props[id] or slot
            end
        end
    end

    local prop = tonumber(item.prop)

    if prop then
        return slotLookup.props[prop]
    end

    local component = tonumber(item.component)

    return component and slotLookup.components[component] or nil
end

---@param item table
---@return { components: table[], props: table[] }
function Shop.getClothingItemApply(item)
    local apply = { components = {}, props = {} }
    local drawable = tonumber(item.drawable) or 0
    local texture = tonumber(item.texture) or 0

    if tonumber(item.prop) then
        apply.props[1] = { prop_id = tonumber(item.prop), drawable = drawable, texture = texture }
    elseif tonumber(item.component) then
        apply.components[1] = { component_id = tonumber(item.component), drawable = drawable, texture = texture }
    end

    return apply
end

---@param source Source
---@return table[]
function Shop.buildOwnedClothing(source)
    local entries = {}

    for _, slot in ipairs(Shop.getClothingSlots()) do
        entries[#entries + 1] = {
            clothingId = Shop.DEFAULT_CLOTHING_ID,
            itemId = Shop.DEFAULT_CLOTHING_ID,
            category = slot,
            label = 'Default',
            imageKey = ('clothing/default/%s.svg'):format(slot),
            rarity = 'common',
            apply = Shop.getDefaultClothingApply(slot),
        }
    end

    local owned = Shop.getOwnedByCategory(source, 'clothing')

    for index = 1, #owned do
        local item = owned[index]
        local slot = Shop.getClothingSlotOf(item)

        if slot then
            entries[#entries + 1] = {
                clothingId = item.id,
                itemId = item.id,
                category = slot,
                label = item.label,
                imageKey = item.image or ('clothing/default/%s.svg'):format(slot),
                rarity = Shop.config.rarityOrder[item.rarity] and item.rarity or 'common',
                apply = Shop.getClothingItemApply(item),
            }
        end
    end

    return entries
end

---@param source Source
---@return table<string, string>
function Shop.buildEquippedClothing(source)
    local stored = Shop.get(source, Shop.keys.clothing, nil)
    local equipped = {}

    if type(stored) ~= 'table' then
        stored = {}
    end

    for _, slot in ipairs(Shop.getClothingSlots()) do
        local itemId = stored[slot]

        equipped[slot] = (itemId and Shop.owns(source, itemId)) and itemId or Shop.DEFAULT_CLOTHING_ID
    end

    return equipped
end
