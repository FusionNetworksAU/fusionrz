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
    ---Items per column of the daily store. The NUI renders it as two columns.
    dailyColumnSize = 4,

    ---Coins to reroll the daily rotation early.
    dailyRefreshPrice = 250,

    ---Hour the rotation turns over, server local time.
    dailyResetHour = 0,

    ---Cap on the featured strip, which is the catalogue's priciest rows.
    featuredCount = 6,

    refunds = {
        startingTokens = 2,

        ---An item can only be handed back inside this window, so a rotation
        ---cannot be farmed by buying and refunding repeatedly.
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

---The shape the NUI renders an item in, everywhere it renders one.
---@param item table
---@param amount integer?
---@return table
function Shop.toEntry(item, amount)
    return {
        itemId = item.id,
        id = item.id,
        label = item.label,
        category = item.category,
        categoryLabel = Shop.categories[item.category],
        image = item.image,
        rarity = item.rarity,
        price = item.price,
        description = item.description,
        amount = amount or 1,
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
    return core:OwnsItem(source, itemId) == true
end

---Everything the player owns, as catalogue rows.
---@param source Source
---@return table[]
function Shop.getOwnedItems(source)
    local owned = core:GetUsableTypeIds(source)
    local items = {}

    for index = 1, #owned do
        local item = Shop.getItem(owned[index])

        if item then
            items[#items + 1] = item
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
