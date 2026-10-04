---@param source Source
---@param itemId string?
---@param category ItemCategory
---@return boolean allowed
---@return string? error
local function canEquip(source, itemId, category)
    if itemId == nil or itemId == '' then
        return true
    end

    local item = Shop.getItem(itemId) --[[@as table]]

    if not item or item.category ~= category then
        return false, 'That is not a valid item.'
    end

    if not Shop.owns(source, itemId) then
        return false, 'You do not own that.'
    end

    return true
end

---@param source Source
---@param key string
---@param category ItemCategory
---@param itemId string?
---@return boolean success
---@return string? error
local function equipSingle(source, key, category, itemId)
    local allowed, err = canEquip(source, itemId, category)

    if not allowed then
        return false, err
    end

    Shop.set(source, key, itemId ~= '' and itemId or nil)
    Shop.pushAll(source)

    return true
end

---@param itemId string?
lib.callback.register('shop:server:equipSound', function(source, itemId)
    return equipSingle(source, Shop.keys.sound, 'sounds', itemId)
end)

---@param itemId string?
lib.callback.register('shop:server:equipBackground', function(source, itemId)
    return equipSingle(source, Shop.keys.background, 'backgrounds', itemId)
end)

---@param itemId string?
lib.callback.register('shop:server:equipPlate', function(source, itemId)
    return equipSingle(source, Shop.keys.plate, 'plates', itemId)
end)

---@param itemId string?
lib.callback.register('shop:server:equipDecoration', function(source, itemId)
    return equipSingle(source, Shop.keys.decoration, 'decorations', itemId)
end)

---@param itemId string?
lib.callback.register('shop:server:equipChatColor', function(source, itemId)
    return equipSingle(source, Shop.keys.chatColor, 'chat_colors', itemId)
end)

---@param source Source
---@param key string
---@param category ItemCategory
---@param slot string?
---@param itemId string?
---@return boolean success
---@return string? error
local function equipSlotted(source, key, category, slot, itemId)
    local allowed, err = canEquip(source, itemId, category)

    if not allowed then
        return false, err
    end

    local equipped = Shop.get(source, key, nil)

    if type(equipped) ~= 'table' then
        equipped = {}
    end

    local slotKey = slot or itemId

    if not slotKey then
        return false, 'Nothing to equip.'
    end

    equipped[slotKey] = itemId ~= '' and itemId or nil

    Shop.set(source, key, equipped)
    Shop.pushAll(source)

    return true
end

---Returns, on success, the slot and what to put on, so the client can dress
---the ped without its owned list being current (equipping straight after a
---purchase races the profile refresh).
---@param data { category: string?, itemId: string? }
---@return boolean success
---@return string slotOrError
---@return { components: table[], props: table[] }? apply
lib.callback.register('shop:server:equipClothing', function(source, data)
    if type(data) ~= 'table' then
        return false, 'Invalid request.'
    end

    local itemId = data.itemId
    local slot = data.category
    local isDefault = itemId == Shop.DEFAULT_CLOTHING_ID or itemId == nil or itemId == ''
    local item = not isDefault and Shop.getItem(itemId) or nil

    -- Store purchases and outfit bundles equip by item alone.
    if slot == nil and item then
        slot = Shop.getClothingSlotOf(item)
    end

    if not Shop.isClothingSlot(slot) then
        return false, 'Invalid request.'
    end

    if not isDefault and (not item or Shop.getClothingSlotOf(item) ~= slot) then
        return false, 'That does not go in this slot.'
    end

    -- The Default piece is the empty slot: clearing it is what puts it on.
    local ok, err = equipSlotted(source, Shop.keys.clothing, 'clothing', slot, isDefault and '' or itemId)

    if not ok then
        return false, err
    end

    return true, slot, isDefault and Shop.getDefaultClothingApply(slot) or Shop.getClothingItemApply(item)
end)

---@param data { category: string?, itemId: string?, equip: boolean? }
lib.callback.register('shop:server:equipTattoo', function(source, data)
    if type(data) ~= 'table' then
        return false, 'Invalid request.'
    end

    -- A tattoo toggles rather than swaps: `equip == false` clears the zone.
    local itemId = data.equip == false and nil or data.itemId

    return equipSlotted(source, Shop.keys.tattoos, 'tattoos', data.category or data.itemId, itemId)
end)

---@param source Source
---@param weaponName string
---@return table[] skins
---@return table<string, boolean> favorited
local function getSkinsForWeapon(source, weaponName)
    local owned = Shop.getOwnedByCategory(source, 'weapons')
    local favorites = Shop.get(source, Shop.keys.favoriteSkins, {})
    local skins = {}
    local favorited = {}

    for index = 1, #owned do
        local item = owned[index]

        if item.baseWeapon == weaponName then
            skins[#skins + 1] = Shop.toEntry(item)

            if type(favorites) == 'table' and favorites[item.id] then
                favorited[item.id] = true
            end
        end
    end

    return skins, favorited
end

---@param weaponName string
lib.callback.register('shop:server:getSkinsForWeapon', function(source, weaponName)
    if type(weaponName) ~= 'string' then
        return {}, {}
    end

    return getSkinsForWeapon(source, weaponName)
end)

---@param categoryKey string
---@param weaponName string
---@param skinId string?
---@return boolean success
lib.callback.register('shop:server:equipProfileSkin', function(source, categoryKey, weaponName, skinId)
    if type(weaponName) ~= 'string' then
        return false
    end

    local allowed = canEquip(source, skinId, 'weapons')

    if not allowed then
        return false
    end

    local equipped = Shop.get(source, Shop.keys.weaponSkins, nil)

    if type(equipped) ~= 'table' then
        equipped = {}
    end

    equipped[weaponName] = skinId ~= '' and skinId or nil

    Shop.set(source, Shop.keys.weaponSkins, equipped)
    Shop.pushAll(source)

    Shop.log(('%s equipped skin %s on %s (%s)'):format(
        Shop.getUserId(source), skinId or 'none', weaponName, categoryKey or 'unknown'
    ))

    return true
end)

---Favourites are display-only -- they pin a skin to the top of its list -- so
---the only rule is that you own what you pin.
---@param baseSkinId string
---@param skinId string
---@param enabled boolean
---@return boolean success
lib.callback.register('shop:server:setFavoriteSkin', function(source, baseSkinId, skinId, enabled)
    if type(skinId) ~= 'string' or not Shop.owns(source, skinId) then
        return false
    end

    local favorites = Shop.get(source, Shop.keys.favoriteSkins, nil)

    if type(favorites) ~= 'table' then
        favorites = {}
    end

    favorites[skinId] = enabled == true or nil

    Shop.set(source, Shop.keys.favoriteSkins, favorites)

    return true
end)

---@param skinId string
---@param enabled boolean
---@return boolean success
lib.callback.register('shop:server:setFavoriteClothing', function(source, skinId, enabled)
    if type(skinId) ~= 'string' or not Shop.owns(source, skinId) then
        return false
    end

    local favorites = Shop.get(source, Shop.keys.favoriteClothing, nil)

    if type(favorites) ~= 'table' then
        favorites = {}
    end

    favorites[skinId] = enabled == true or nil

    Shop.set(source, Shop.keys.favoriteClothing, favorites)
    Shop.pushAll(source)

    return true
end)

-- ---------------------------------------------------------------- outfits --

---An outfit item is a bundle: its `data.items` names the clothing ids it puts
---on. The client equips each one in turn, so all this has to return is the
---list -- filtered to what the player actually owns, because an outfit may
---have been bought before one of its pieces was retired.
---@param itemId string
---@return string[]?
lib.callback.register('shop:server:getOutfitLinkedItems', function(source, itemId)
    local item = Shop.getItem(itemId) --[[@as table]]

    if not item then
        return nil
    end

    local linked = item.items or (item.data and item.data.items)

    if type(linked) ~= 'table' then
        return nil
    end

    local owned = {}

    for index = 1, #linked do
        local clothingId = linked[index]

        if Shop.owns(source, clothingId) then
            owned[#owned + 1] = clothingId
        end
    end

    return owned
end)

-- --------------------------------------------------------------- emotes ----

---@param slotIndex integer
---@param emoteId string?
---@return boolean success
---@return string? error
lib.callback.register('shop:server:equipEmoteSlot', function(source, slotIndex, emoteId)
    local index = math.floor(tonumber(slotIndex) or 0)
    local slotCount = Shop.get(source, Shop.keys.emoteSlotCount, Shop.tuning.emotes.defaultSlots)

    if index < 1 or index > slotCount then
        return false, 'That slot does not exist.'
    end

    local allowed, err = canEquip(source, emoteId, 'emotes')

    if not allowed then
        return false, err
    end

    local slots = Shop.get(source, Shop.keys.emoteSlots, nil)

    if type(slots) ~= 'table' then
        slots = {}
    end

    -- Keyed by the string form of the index because that is how the NUI reads
    -- it back (ui/client/uis/emotes.lua indexes slots[tostring(slotIndex)]).
    slots[tostring(index)] = emoteId ~= '' and emoteId or nil

    Shop.set(source, Shop.keys.emoteSlots, slots)
    Shop.pushAll(source)

    return true
end)

---The catalogue row the client needs to actually show or play something: the
---component numbers for clothing, the overlay for a tattoo, the anim for an
---emote, the sound name for a sound. Served from here rather than shipped
---with the owned lists because the client only ever needs one at a time, and
---the store previews items the player does not own yet.
---@param itemId string
---@return table?
lib.callback.register('shop:server:getPreviewData', function(_, itemId)
    local item = Shop.getItem(itemId) --[[@as table]]

    if not item then
        return nil
    end

    local data = item.data or {}

    return {
        id = item.id,
        category = item.category,
        label = item.label,
        -- Core flattens an item's `data` JSON onto the row, but older rows
        -- may still carry it nested, so both are read.
        component = item.component or data.component,
        drawable = item.drawable or data.drawable,
        texture = item.texture or data.texture,
        prop = item.prop or data.prop,
        collection = item.collection or data.collection,
        overlay = item.overlay or data.overlay,
        baseWeapon = item.baseWeapon or data.baseWeapon,
        dictionary = item.dictionary or data.dictionary,
        animation = item.animation or data.animation,
        soundName = item.soundName or data.soundName,
        soundSet = item.soundSet or data.soundSet,
        colour = item.colour or data.colour,
    }
end)

exports('GetEquippedWeaponSkins', function(source)
    return Shop.get(source, Shop.keys.weaponSkins, {})
end)

exports('GetEquippedItem', function(source, category)
    local key = Shop.keys[category]

    return key and Shop.get(source, key, nil) or nil
end)
