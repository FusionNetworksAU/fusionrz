---@alias ItemCategory
---| 'weapons'
---| 'sounds'
---| 'backgrounds'
---| 'plates'
---| 'decorations'
---| 'chat_colors'
---| 'clothing'
---| 'livery'
---| 'calling_cards'
---| 'emotes'
---| 'tattoos'
---| 'smokes'
---| 'charms'

---@class Item
---@field id string
---@field category ItemCategory
---@field label string
---@field description? string
---@field ace? string
---@field image? string
---@field rarity? string
---@field price? integer
---@field purchasable boolean
---@field enabled boolean
---@field sortOrder integer
---@field data table

---@class WeaponItem : Item
---@field baseWeapon WeaponBaseType
---@field tint? integer
---@field components? string[]

---@class PlateItem : Item
---@field plateText? string

---@class ChatColorItem : Item
---@field colour string

---@class ClothingItem : Item
---@field drawable? integer
---@field texture? integer
---@field component? integer
---@field prop? integer

---@class LiveryItem : Item
---@field spawncode string
---@field livery integer

---@class CallingCardItem : Item
---@class EmoteItem : Item
---@field dictionary? string
---@field animation? string

---@class TattooItem : Item
---@field collection? string
---@field overlay? string

---@class SmokeItem : Item
---@class CharmItem : Item

---@class HandItem
---@field id string
---@field label string
---@field model string
---@field bone? integer
---@field offset? vector3
---@field rotation? vector3

---@alias ItemsLookup table<string, Item>
---@alias WeaponItemsLooukp table<string, WeaponItem>
---@alias PlateItemsLookup table<string, PlateItem>
---@alias ChatColorItemsLookup table<string, ChatColorItem>
---@alias ClothingItemsLookup table<string, ClothingItem>
---@alias LiveryItemsLookup table<string, LiveryItem>
---@alias CallingCardItemsLookup table<string, CallingCardItem>
---@alias EmoteItemsLookup table<string, EmoteItem>
---@alias TattooItemsLookup table<string, TattooItem>
---@alias SmokeItemsLookup table<string, SmokeItem>
---@alias CharmItemsLookup table<string, CharmItem>
---@alias HandItemsLookup table<string, HandItem>

---@type table<ItemCategory, true>
local validCategories = {
    weapons = true,
    sounds = true,
    backgrounds = true,
    plates = true,
    decorations = true,
    chat_colors = true,
    clothing = true,
    livery = true,
    calling_cards = true,
    emotes = true,
    tattoos = true,
    smokes = true,
    charms = true,
}

Core.itemCategories = validCategories

---@param category string?
---@return boolean
function Core.isItemCategory(category)
    return category ~= nil and validCategories[category] == true
end

---The ace an item grants. Kept here rather than in the DB row so a renamed
---category can never desync the two halves of the lookup that
---imports/items.lua does in getItemIdByAce.
---@param category ItemCategory
---@param itemId string
---@return string ace
function Core.buildItemAce(category, itemId)
    return ('%s.%s'):format(category, itemId)
end

return validCategories
