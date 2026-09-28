local core = exports.core

---@type ItemsLookup
local items = {}

---@type table<ItemCategory, ItemsLookup>
local itemsByCategory = {}

---@type HandItemsLookup
local handItems = {}

local isReady = false

---@type fun()[]
local readyCallbacks = {}

local function rebuildCategoryLookup()
    itemsByCategory = {}

    for itemId, itemData in pairs(items) do
        local categoryLookup = itemsByCategory[itemData.category]

        if not categoryLookup then
            categoryLookup = {}
            itemsByCategory[itemData.category] = categoryLookup
        end

        categoryLookup[itemId] = itemData
    end
end

local function seedFromCore()
    items = core:GetAllItems()
    handItems = core:GetAllHandItems()

    rebuildCategoryLookup()

    isReady = true

    for _, readyCallback in ipairs(readyCallbacks) do
        readyCallback()
    end

    collectgarbage("collect")
end

---@return boolean
local function areItemsReady()
    return isReady
end

local function awaitReady()
    while not isReady do
        Wait(50)
    end
end

---@param callback fun()
local function onReady(callback)
    readyCallbacks[#readyCallbacks + 1] = callback

    if isReady then
        callback()
    end
end

---@param itemId string
---@return Item?
local function getItem(itemId)
    return items[itemId]
end

---@return ItemsLookup
local function getAllItems()
    return items
end

---@param itemId string
---@return WeaponItem?
local function getWeaponItem(itemId)
    local weaponItem = items[itemId] ---@cast weaponItem WeaponItem
    if weaponItem and weaponItem.category == 'weapons' then
        return weaponItem
    end
    return nil
end

---@return WeaponItemsLooukp
local function getAllWeapons()
    local categoryLookup = itemsByCategory['weapons'] ---@cast categoryLookup WeaponItemsLooukp
    return categoryLookup or {}
end

---@param baseWeapon WeaponBaseType
---@return WeaponItemsLooukp
local function getWeaponItemsByBase(baseWeapon)
    ---@type WeaponItemsLooukp
    local weaponItems = {}

    for weaponId, weaponItem in pairs(getAllWeapons()) do
        if weaponItem.baseWeapon == baseWeapon then
            weaponItems[weaponId] = weaponItem
        end
    end

    return weaponItems
end

---@param itemId string
---@return Item?
local function getSoundItem(itemId)
    local soundItem = items[itemId]
    if soundItem and soundItem.category == 'sounds' then
        return soundItem
    end
    return nil
end

---@return ItemsLookup
local function getAllSounds()
    local categoryLookup = itemsByCategory['sounds']
    return categoryLookup or {}
end

---@param itemId string
---@return Item?
local function getBackgroundItem(itemId)
    local backgroundItem = items[itemId]
    if backgroundItem and backgroundItem.category == 'backgrounds' then
        return backgroundItem
    end
    return nil
end

---@return ItemsLookup
local function getAllBackgrounds()
    local categoryLookup = itemsByCategory['backgrounds']
    return categoryLookup or {}
end

---@param itemId string
---@return PlateItem?
local function getPlateItem(itemId)
    local plateItem = items[itemId] ---@cast plateItem PlateItem
    if plateItem and plateItem.category == 'plates' then
        return plateItem
    end
    return nil
end

---@return PlateItemsLookup
local function getAllPlates()
    local categoryLookup = itemsByCategory['plates'] ---@cast categoryLookup PlateItemsLookup
    return categoryLookup or {}
end

---@param itemId string
---@return Item?
local function getDecorationItem(itemId)
    local decorationItem = items[itemId]
    if decorationItem and decorationItem.category == 'decorations' then
        return decorationItem
    end
    return nil
end

---@return ItemsLookup
local function getAllDecorations()
    local categoryLookup = itemsByCategory['decorations']
    return categoryLookup or {}
end

---@param itemId string
---@return ChatColorItem?
local function getChatColorItem(itemId)
    local chatColorItem = items[itemId] ---@cast chatColorItem ChatColorItem
    if chatColorItem and chatColorItem.category == 'chat_colors' then
        return chatColorItem
    end
    return nil
end

---@return ChatColorItemsLookup
local function getAllChatColors()
    local categoryLookup = itemsByCategory['chat_colors'] ---@cast categoryLookup ChatColorItemsLookup
    return categoryLookup or {}
end

---@param itemId string
---@return ClothingItem?
local function getClothingItem(itemId)
    local clothingItem = items[itemId] ---@cast clothingItem ClothingItem
    if clothingItem and clothingItem.category == 'clothing' then
        return clothingItem
    end
    return nil
end

---@return ClothingItemsLookup
local function getAllClothing()
    local categoryLookup = itemsByCategory['clothing'] ---@cast categoryLookup ClothingItemsLookup
    return categoryLookup or {}
end

---@param itemId string
---@return LiveryItem?
local function getLiveryItem(itemId)
    local liveryItem = items[itemId] ---@cast liveryItem LiveryItem
    if liveryItem and liveryItem.category == 'livery' then
        return liveryItem
    end
    return nil
end

---@return LiveryItemsLookup
local function getAllLiveries()
    local categoryLookup = itemsByCategory['livery'] ---@cast categoryLookup LiveryItemsLookup
    return categoryLookup or {}
end

---@param spawncode string
---@return LiveryItemsLookup
local function getLiveryItemsBySpawncode(spawncode)
    ---@type LiveryItemsLookup
    local liveryItems = {}

    for liveryId, liveryItem in pairs(getAllLiveries()) do
        if liveryItem.spawncode == spawncode then
            liveryItems[liveryId] = liveryItem
        end
    end

    return liveryItems
end

---@param itemId string
---@return HandItem?
local function getHandItem(itemId)
    return handItems[itemId]
end

---@return HandItemsLookup
local function getAllHandItems()
    return handItems
end

---@param itemId string
---@return CallingCardItem?
local function getCardItem(itemId)
    local cardItem = items[itemId] ---@cast cardItem CallingCardItem
    if cardItem and cardItem.category == 'calling_cards' then
        return cardItem
    end
    return nil
end

---@return CallingCardItemsLookup
local function getAllCards()
    local categoryLookup = itemsByCategory['calling_cards'] ---@cast categoryLookup CallingCardItemsLookup
    return categoryLookup or {}
end

---@param itemId string
---@return EmoteItem?
local function getEmoteItem(itemId)
    local emoteItem = items[itemId] ---@cast emoteItem EmoteItem
    if emoteItem and emoteItem.category == 'emotes' then
        return emoteItem
    end
    return nil
end

---@return EmoteItemsLookup
local function getAllEmotes()
    local categoryLookup = itemsByCategory['emotes'] ---@cast categoryLookup EmoteItemsLookup
    return categoryLookup or {}
end

---@param itemId string
---@return TattooItem?
local function getTattooItem(itemId)
    local tattooItem = items[itemId] ---@cast tattooItem TattooItem
    if tattooItem and tattooItem.category == 'tattoos' then
        return tattooItem
    end
    return nil
end

---@return TattooItemsLookup
local function getAllTattoos()
    local categoryLookup = itemsByCategory['tattoos'] ---@cast categoryLookup TattooItemsLookup
    return categoryLookup or {}
end

---@param itemId string
---@return SmokeItem?
local function getSmokeItem(itemId)
    local smokeItem = items[itemId] ---@cast smokeItem SmokeItem
    if smokeItem and smokeItem.category == 'smokes' then
        return smokeItem
    end
    return nil
end

---@return SmokeItemsLookup
local function getAllSmokes()
    local categoryLookup = itemsByCategory['smokes'] ---@cast categoryLookup SmokeItemsLookup
    return categoryLookup or {}
end

---@param itemId string
---@return CharmItem?
local function getCharmItem(itemId)
    local charmItem = items[itemId] ---@cast charmItem CharmItem
    if charmItem and charmItem.category == 'charms' then
        return charmItem
    end
    return nil
end

---@return CharmItemsLookup
local function getAllCharms()
    local categoryLookup = itemsByCategory['charms'] ---@cast categoryLookup CharmItemsLookup
    return categoryLookup or {}
end

---@param ace string
---@return string? itemId
local function getItemIdByAce(ace)
    if type(ace) ~= 'string' then
        return nil
    end

    local dotIndex = ace:find('.', 1, true)
    if not dotIndex then
        return nil
    end

    local itemId = ace:sub(dotIndex + 1)

    local itemData = items[itemId]
    if itemData and itemData.ace == ace then
        return itemId
    end

    return nil
end

AddEventHandler('core:itemsReady', seedFromCore)

---@param itemId string
AddEventHandler('core:onItemDeletedById', function(itemId)
    local itemData = items[itemId]
    if not itemData then
        return
    end

    items[itemId] = nil

    local categoryLookup = itemsByCategory[itemData.category]
    if categoryLookup then
        categoryLookup[itemId] = nil
    end
end)

if GetResourceState('core') == 'started' and core:AreItemsReady() then
    seedFromCore()
end

return {
    AreItemsReady = areItemsReady,
    AwaitReady = awaitReady,
    OnReady = onReady,
    GetItem = getItem,
    GetAllItems = getAllItems,
    GetWeaponItem = getWeaponItem,
    GetWeaponItemsByBase = getWeaponItemsByBase,
    GetAllWeapons = getAllWeapons,
    GetSoundItem = getSoundItem,
    GetAllSounds = getAllSounds,
    GetBackgroundItem = getBackgroundItem,
    GetAllBackgrounds = getAllBackgrounds,
    GetPlateItem = getPlateItem,
    GetAllPlates = getAllPlates,
    GetDecorationItem = getDecorationItem,
    GetAllDecorations = getAllDecorations,
    GetChatColorItem = getChatColorItem,
    GetAllChatColors = getAllChatColors,
    GetClothingItem = getClothingItem,
    GetAllClothing = getAllClothing,
    GetLiveryItem = getLiveryItem,
    GetLiveryItemsBySpawncode = getLiveryItemsBySpawncode,
    GetAllLiveries = getAllLiveries,
    GetHandItem = getHandItem,
    GetAllHandItems = getAllHandItems,
    GetCardItem = getCardItem,
    GetAllCards = getAllCards,
    GetEmoteItem = getEmoteItem,
    GetAllEmotes = getAllEmotes,
    GetTattooItem = getTattooItem,
    GetAllTattoos = getAllTattoos,
    GetSmokeItem = getSmokeItem,
    GetAllSmokes = getAllSmokes,
    GetCharmItem = getCharmItem,
    GetAllCharms = getAllCharms,
    GetItemIdByAce = getItemIdByAce,
}
