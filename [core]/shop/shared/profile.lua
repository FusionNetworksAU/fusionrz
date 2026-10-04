---Where a player's shop state is kept, and how it is read back.
---
---Not in a table of our own: equipped cosmetics, favourites, emote slots and
---refund tokens all live in core's per-player metadata blob. It is already
---loaded with the player, already saved on drop, and it is where
---ui/server/uis/profile.lua keeps `name_color` and `chat_tag` -- so a colour
---picked in the settings screen and one picked in the store are the same
---setting rather than two that have to be kept in step.

-- The manifest loads these alphabetically, so shop.lua is not necessarily
-- first. Every file in this folder creates the table if it is not there yet.
Shop = Shop or {}
local core = exports.core

Shop.keys = {
    sound = 'equipped_sound',
    background = 'equipped_background',
    plate = 'equipped_plate',
    decoration = 'equipped_decoration',
    chatColor = 'chat_text_color',
    nameColor = 'name_color',
    clothing = 'equipped_clothing',
    tattoos = 'equipped_tattoos',
    weaponSkins = 'equipped_weapon_skins',
    favoriteSkins = 'favorite_weapon_skins',
    favoriteClothing = 'favorite_clothing',
    emoteSlots = 'emote_slots',
    emoteSlotCount = 'emote_slot_count',
    refundTokens = 'refund_tokens',
    creatorCode = 'creator_code',
    customPlate = 'custom_plate',
    dailySeed = 'daily_store_seed',
    dailyDay = 'daily_store_day',
}

---@param source Source
---@param key string
---@param fallback any
---@return any
function Shop.get(source, key, fallback)
    local value = core:GetMetadata(source, key)

    if value == nil then
        return fallback
    end

    return value
end

---@param source Source
---@param key string
---@param value any
---@return boolean
function Shop.set(source, key, value)
    return core:SetMetadata(source, key, value)
end

---@param source Source
---@param category string
---@return table[]
function Shop.buildOwned(source, category)
    local items = Shop.getOwnedByCategory(source, category)
    local entries = {}

    for index = 1, #items do
        entries[index] = Shop.toEntry(items[index])
    end

    return Shop.sortByRarity(entries)
end

---Clothing and tattoos are stored as slot -> itemId, but the NUI reads them
---as [itemId, slot] pairs, so the shape is turned around on the way out.
---@param source Source
---@param key string
---@return table[]
function Shop.buildEquippedPairs(source, key)
    local stored = Shop.get(source, key, nil)

    if type(stored) ~= 'table' then
        return {}
    end

    local out = {}

    for slot, itemId in pairs(stored) do
        out[#out + 1] = { itemId, slot }
    end

    return out
end

---The whole per-player snapshot, in one piece. The client pulls this and
---fans it out into ui's `set*` exports: those are client exports, so the
---server can never call them itself.
---@param source Source
---@return table?
function Shop.buildProfile(source)
    if not Shop.getUserId(source) then
        return nil
    end

    return {
        owned = {
            -- Per slot, Default piece first: shared/clothing.lua.
            clothing = Shop.buildOwnedClothing(source),
            tattoos = Shop.buildOwned(source, 'tattoos'),
            sounds = Shop.buildOwned(source, 'sounds'),
            plates = Shop.buildOwned(source, 'plates'),
            backgrounds = Shop.buildOwned(source, 'backgrounds'),
            decorations = Shop.buildOwned(source, 'decorations'),
            emotes = Shop.buildOwned(source, 'emotes'),
            charms = Shop.buildOwned(source, 'charms'),
            chatColors = Shop.buildOwned(source, 'chat_colors'),
            callingCards = Shop.buildOwned(source, 'calling_cards'),
            purchasedIds = core:GetUsableTypeIds(source) or {},
        },
        equipped = {
            -- slot -> clothingId (the Clothing page indexes it by slot), unlike tattoos.
            clothing = Shop.buildEquippedClothing(source),
            tattoos = Shop.buildEquippedPairs(source, Shop.keys.tattoos),
            soundId = Shop.get(source, Shop.keys.sound, nil),
            plateId = Shop.get(source, Shop.keys.plate, nil),
            backgroundId = Shop.get(source, Shop.keys.background, nil),
            decorationId = Shop.get(source, Shop.keys.decoration, nil),
            chatColorId = Shop.get(source, Shop.keys.chatColor, nil),
            weaponSkins = Shop.get(source, Shop.keys.weaponSkins, {}),
            favoriteSkins = Shop.get(source, Shop.keys.favoriteSkins, {}),
            favoriteClothing = Shop.get(source, Shop.keys.favoriteClothing, {}),
            emoteSlots = Shop.get(source, Shop.keys.emoteSlots, {}),
            emoteSlotCount = Shop.get(source, Shop.keys.emoteSlotCount, Shop.tuning.emotes.defaultSlots),
        },
        bodyTypes = Shop.data.bodyTypes,
        creatorCode = Shop.get(source, Shop.keys.creatorCode, nil),
        refundTokens = Shop.get(source, Shop.keys.refundTokens, Shop.tuning.refunds.startingTokens),
    }
end

---Tells one client its data changed. One message rather than twenty pushes;
---the client answers it by pulling the snapshot above.
---@param source Source
function Shop.pushAll(source)
    TriggerClientEvent('shop:client:refresh', source)
end
