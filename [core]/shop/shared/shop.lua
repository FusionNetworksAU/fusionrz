---Shop state and the helpers every server file shares.
---
---Loaded ahead of server/*.lua by the manifest, so `Shop` exists before
---anything reaches for it.
---
---Two config surfaces meet here. `Shop.config` is config/shared.lua, which
---already existed and owns the prices and the rarity order. `Shop.tuning` is
---everything the storefront needs that those files have no key for -- the
---rotation size, the refund rules, the gift caps, the creator share. It lives
---in code rather than in a sixth config file because the manifest's `files`
---list is what the client can read, and none of this is read there.

Shop = Shop or {}

Shop.config = require 'config.shared'
Shop.categories = require 'config.categories'
Shop.data = require 'config.data'

Shop.tuning = {
    dailyColumnSize = 4,

    dailyRefreshPrice = 250,

    dailyRefreshLimit = 3,

    dailyResetHour = 0,

    featuredCount = 6,

    refunds = {
        startingTokens = 2,

        windowSeconds = 7 * 24 * 60 * 60,

        ---Categories that can never be refunded, because equipping them
        ---changes something that cannot be taken back cleanly.
        blocked = {
            emotes = true,
        },
    },

    gifts = {
        maxMessageLength = 256,

        ---Unclaimed gifts per recipient, so a mailbox is not free storage.
        maxPending = 25,
    },

    emotes = {
        defaultSlots = 8,
        maxSlots = 8,
        blockInVehicle = true,
        blockWhileDead = true,
    },

    creators = {
        ---Fraction of a purchase credited to the code's owner, overridden per
        ---code by shop_creator_codes.share.
        defaultShare = 0.05,

        codeMinLength = 2,
        codeMaxLength = 32,

        ---Dashboard windows, in days. 0 is all time.
        timespans = {
            ['7d'] = 7,
            ['30d'] = 30,
            ['90d'] = 90,
            ['all'] = 0,
        },

        topSpendersPageSize = 10,
    },

    ---Where the preview ped stands: high above the map, so nothing walks
    ---through the shot. The camera settings themselves are config/preview.lua.
    previewCoords = vec4(-3675.2393, -1055.2307, 1600.0, 180.0),

    maleModel = `mp_m_freemode_01`,
    femaleModel = `mp_f_freemode_01`,

    ---Try-before-you-buy range.
    testGun = {
        coords = vec4(-3675.2393, -1055.2307, 1507.8354, 182.6257),
        ammo = 250,
    },
}

local core = exports.core

---@param source Source
---@return table?
function Shop.getPlayer(source)
    return core:GetPlayerData(source)
end

---@param source Source
---@return integer?
function Shop.getUserId(source)
    local data = core:GetPlayerData(source)

    return data and data.userId or nil
end

---The catalogue row behind an item id, or nil if it is retired or unknown.
---@param itemId string?
---@return table?
function Shop.getItem(itemId)
    if type(itemId) ~= 'string' then
        return nil
    end

    local item = core:GetItem(itemId)

    return item and item.enabled and item or nil
end

---Rarities the NUI has a colour for. It looks the colour up unguarded, so any
---other value (or none) crashed the whole UI; those fall back to common.
local NUI_RARITIES = {
    common = true, uncommon = true, rare = true, epic = true, legendary = true,
    mythical = true, gang = true, event = true, battlepass = true,
}

---The game weapon behind an item. A plain gun row (shop_weapons.sql) has no
---baseWeapon in its data because its id already is the weapon name, so that
---is used; skins and other weapon cosmetics name theirs in data.
---@param item table
---@return string?
function Shop.getBaseWeapon(item)
    if item.baseWeapon then
        return item.baseWeapon
    end

    if item.category == 'weapons' and type(item.id) == 'string' and item.id:find('^weapon_') then
        return item.id:upper()
    end

    return nil
end

---Which 3D preview the store page runs for a category (the NUI's own list:
---outfit, weapon, emote, tattoo, vehicle, smoke, charm). Anything else shows
---just its picture.
local PREVIEW_TYPES = {
    weapons = 'weapon',
    clothing = 'outfit',
    outfits = 'outfit',
    emotes = 'emote',
    tattoos = 'tattoo',
    livery = 'vehicle',
    smokes = 'smoke',
    charms = 'charm',
}

---The picture for an item, falling back when its row has none: a gun uses
---its weapon icon (ui cdn/weapons/<name>.webp, which the rest of the UI
---already reads), a clothing piece its slot icon. A missing image drew a
---broken-image box on the card.
---@param item table
---@return string?
function Shop.getItemImage(item)
    if type(item.image) == 'string' and item.image ~= '' then
        return item.image
    end

    local baseWeapon = Shop.getBaseWeapon(item)

    if baseWeapon then
        return ('weapons/%s.webp'):format(baseWeapon:lower())
    end

    if item.category == 'clothing' and Shop.getClothingSlotOf then
        local slot = Shop.getClothingSlotOf(item)

        if slot then
            return ('clothing/default/%s.svg'):format(slot)
        end
    end

    return nil
end

---The shape the NUI renders an item in, everywhere it renders one.
---@param item table
---@param amount integer?
---@return table
function Shop.toEntry(item, amount)
    local rarity = NUI_RARITIES[item.rarity] and item.rarity or 'common'
    local image = Shop.getItemImage(item)

    return {
        itemId = item.id,
        id = item.id,
        label = item.label or item.id,
        category = item.category,
        categoryLabel = Shop.categories[item.category],
        image = image,
        rarity = rarity,
        price = item.price or 0,
        -- The store cards read the price as `coins` (coins.toLocaleString(),
        -- unguarded); without it the first card rendered crashed the UI.
        coins = item.price or 0,
        description = item.description or '',
        amount = amount or 1,
        -- The item page (opened with "View") reads these three unguarded:
        -- what to preview, the "items included" cards, and the tag chips.
        -- A bundle would list several; a single item is just itself.
        previews = {
            {
                itemId = item.id,
                image = image,
                type = PREVIEW_TYPES[item.category] or item.category,
                tags = {},
            },
        },
        cards = {
            { image = image, rarity = rarity, previewItemId = item.id },
        },
        tags = {},
    }
end

---Sorts a list of entries the way the store shows them: rarest first, then by
---name. config/shared.lua's rarityOrder is the authority on "rarest".
---@param entries table[]
---@return table[]
function Shop.sortByRarity(entries)
    local order = Shop.config.rarityOrder

    table.sort(entries, function(a, b)
        local rankA = order[a.rarity] or 100
        local rankB = order[b.rarity] or 100

        if rankA ~= rankB then
            return rankA < rankB
        end

        return (a.label or '') < (b.label or '')
    end)

    return entries
end

---@param source Source
---@param itemId string
---@return boolean
function Shop.owns(source, itemId)
    -- Free rows (default_clothing.sql) belong to everyone without an
    -- inventory entry.
    local item = Shop.getItem(itemId)

    if item and item.free then
        return true
    end

    return core:OwnsItem(source, itemId) == true
end

---Free catalogue rows, which every player owns. Sorted so the profile shows
---them in sort_order.
---@return table[]
local function getFreeItems()
    local free = {}

    for _, item in pairs(core:GetAllItems() or {}) do
        if item.enabled and item.free then
            free[#free + 1] = item
        end
    end

    table.sort(free, function(a, b)
        if (a.sortOrder or 0) ~= (b.sortOrder or 0) then
            return (a.sortOrder or 0) < (b.sortOrder or 0)
        end

        return a.id < b.id
    end)

    return free
end

---Everything the player owns, as catalogue rows.
---@param source Source
---@return table[]
function Shop.getOwnedItems(source)
    local owned = core:GetUsableTypeIds(source) or {}
    local items = {}
    local seen = {}

    for index = 1, #owned do
        local item = Shop.getItem(owned[index])

        if item and not seen[item.id] then
            seen[item.id] = true
            items[#items + 1] = item
        end
    end

    local free = getFreeItems()

    for index = 1, #free do
        if not seen[free[index].id] then
            items[#items + 1] = free[index]
        end
    end

    return items
end

---@param source Source
---@param category string
---@return table[]
function Shop.getOwnedByCategory(source, category)
    local owned = Shop.getOwnedItems(source)
    local filtered = {}

    for index = 1, #owned do
        if owned[index].category == category then
            filtered[#filtered + 1] = owned[index]
        end
    end

    return filtered
end

---@param message string
function Shop.log(message)
    core:Log('shop', message)
end
