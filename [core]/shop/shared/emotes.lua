---Emote slots.
---
---A player has a fixed number of slots and puts an owned emote in each. The
---slot map is stored keyed by the STRING form of the index, because that is
---how ui/client/uis/emotes.lua reads it back (slots[tostring(slotIndex)]).

-- The manifest loads these alphabetically, so shop.lua is not necessarily
-- first. Every file in this folder creates the table if it is not there yet.
Shop = Shop or {}
---@param source Source
---@return integer
function Shop.getEmoteSlotCount(source)
    local count = Shop.get(source, Shop.keys.emoteSlotCount, Shop.tuning.emotes.defaultSlots)

    return math.min(Shop.tuning.emotes.maxSlots, math.max(0, math.floor(tonumber(count) or 0)))
end

---@param source Source
---@return table<string, string>
function Shop.getEmoteSlots(source)
    local slots = Shop.get(source, Shop.keys.emoteSlots, nil)

    return type(slots) == 'table' and slots or {}
end

---@param source Source
---@param slotIndex integer
---@param emoteId string?
---@return boolean success
---@return string? error
function Shop.setEmoteSlot(source, slotIndex, emoteId)
    local index = math.floor(tonumber(slotIndex) or 0)

    if index < 1 or index > Shop.getEmoteSlotCount(source) then
        return false, 'That slot does not exist.'
    end

    if emoteId ~= nil and emoteId ~= '' then
        local item = Shop.getItem(emoteId)

        if not item or item.category ~= 'emotes' then
            return false, 'That is not an emote.'
        end

        if not Shop.owns(source, emoteId) then
            return false, 'You do not own that emote.'
        end
    end

    local slots = Shop.getEmoteSlots(source)

    slots[tostring(index)] = (emoteId ~= nil and emoteId ~= '') and emoteId or nil

    Shop.set(source, Shop.keys.emoteSlots, slots)
    Shop.pushAll(source)

    return true
end

---@param source Source
---@param count integer
---@return boolean
function Shop.setEmoteSlotCount(source, count)
    local slots = math.min(Shop.tuning.emotes.maxSlots, math.max(0, math.floor(tonumber(count) or 0)))

    Shop.set(source, Shop.keys.emoteSlotCount, slots)
    Shop.pushAll(source)

    return true
end
