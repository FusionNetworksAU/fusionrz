---The storefront: what is on sale, and buying it.
---
---Nothing here invents an item. The catalogue is core's `items` table, and a
---row is offered for sale only when it is `purchasable`, `enabled` and has a
---price. The rotation is a deterministic shuffle of that set seeded per
---player per day, so a reroll is a new seed rather than a stored list -- there
---is no per-player store table to keep in sync with the catalogue.

local core = exports.core

---@param source Source
---@return Item[]
local function getSellableItems()
    local items = core:GetAllItems() or {}
    local sellable = {}

    for _, item in pairs(items) do
        if item.enabled and item.purchasable and (item.price or 0) > 0 then
            sellable[#sellable + 1] = item
        end
    end

    -- Catalogue order is a hash iteration, which is not stable between
    -- restarts; sorting by id makes the seeded shuffle below reproducible.
    table.sort(sellable, function(a, b)
        return a.id < b.id
    end)

    return sellable
end

---Days since the epoch, rolled at the configured reset hour. This is the
---other half of the rotation seed, so every player's store turns over at the
---same moment without a timer.
---@return integer
local function currentStoreDay()
    local now = os.time() - (Shop.tuning.dailyResetHour * 3600)

    return math.floor(now / 86400)
end

---A xorshift over (seed, index) rather than math.random, because the same
---seed has to give the same store on every call -- including after a restart,
---and without disturbing the global RNG that everything else shares.
---@param seed integer
---@param index integer
---@return integer
local function hash(seed, index)
    local value = (seed * 2654435761 + index * 40503) % 2147483647

    value = value ~ (value >> 13)
    value = (value * 1274126177) % 2147483647

    return value ~ (value >> 16)
end

---@param source Source
---@return integer
local function getSeed(source)
    local day = currentStoreDay()
    local storedDay = Shop.get(source, Shop.keys.dailyDay, nil)
    local seed = Shop.get(source, Shop.keys.dailySeed, nil)

    -- A new day resets the reroll: the seed becomes the day itself, so a
    -- player who never touches the refresh button still gets a new store.
    if storedDay ~= day or type(seed) ~= 'number' then
        seed = day
        Shop.set(source, Shop.keys.dailyDay, day)
        Shop.set(source, Shop.keys.dailySeed, seed)
    end

    return seed
end

---@param source Source
---@param count integer
---@return Item[]
local function pickRotation(source, count)
    local pool = getSellableItems()
    local poolSize = #pool

    if poolSize == 0 then
        return {}
    end

    local seed = getSeed(source) + (Shop.getUserId(source) or 0)
    local picked = {}
    local taken = {}

    -- Sampling without replacement: walk forward from the hashed index until
    -- an untaken slot turns up, which terminates because count <= poolSize.
    for index = 1, math.min(count, poolSize) do
        local slot = (hash(seed, index) % poolSize) + 1

        while taken[slot] do
            slot = (slot % poolSize) + 1
        end

        taken[slot] = true
        picked[#picked + 1] = pool[slot]
    end

    return picked
end

---@param items Item[]
---@return table[]
local function toEntries(items)
    local entries = {}

    for index = 1, #items do
        entries[index] = Shop.toEntry(items[index])
    end

    return entries
end

---Featured is the top of the catalogue by price, not a rotation: it is the
---same for everyone, which is what makes it featured.
---@return table[]
local function buildFeatured()
    local pool = getSellableItems()

    table.sort(pool, function(a, b)
        if a.price ~= b.price then
            return a.price > b.price
        end

        return a.id < b.id
    end)

    local featured = {}

    for index = 1, math.min(Shop.tuning.featuredCount, #pool) do
        featured[index] = Shop.toEntry(pool[index])
    end

    return featured
end

---@param source Source
function Shop.pushStore(source)
    local columnSize = Shop.tuning.dailyColumnSize
    local rotation = pickRotation(source, columnSize * 2)

    local left = {}
    local right = {}

    for index = 1, #rotation do
        local target = index <= columnSize and left or right

        target[#target + 1] = Shop.toEntry(rotation[index])
    end

    TriggerClientEvent('shop:client:setStore', source, {
        daily = {
            title = 'DAILY ITEMS',
            leftItems = left,
            rightItems = right,
        },
        featured = buildFeatured(),
        refreshPrice = Shop.tuning.dailyRefreshPrice,
    })
end

-- ------------------------------------------------------------- purchasing --

---Buys `itemId` for `buyer`, optionally as a gift for someone else. The
---coin move and the ledger row are the same operation as far as callers are
---concerned, so both paths come through here.
---@param source Source
---@param itemId string
---@param creatorCode string?
---@param giftedTo integer? recipient userId, nil for a purchase for self
---@return boolean success
---@return string? error
function Shop.chargeAndRecord(source, itemId, creatorCode, giftedTo)
    local item = Shop.getItem(itemId)

    if not item then
        return false, 'That item is not available.'
    end

    if not item.purchasable or (item.price or 0) <= 0 then
        return false, 'That item is not for sale.'
    end

    local userId = Shop.getUserId(source)

    if not userId then
        return false, 'No player loaded.'
    end

    if not giftedTo and Shop.owns(source, itemId) then
        return false, 'You already own that.'
    end

    local code = Shop.normaliseCreatorCode(creatorCode)

    local charged = core:RemoveCoins(source, item.price, ('shop:%s'):format(itemId))

    if not charged then
        return false, 'You cannot afford that.'
    end

    MySQL.insert.await(
        'INSERT INTO shop_purchases (user_id, item_id, price, creator_code, gifted_to) VALUES (?, ?, ?, ?, ?)',
        { userId, itemId, item.price, code, giftedTo }
    )

    Shop.log(('%s (%s) bought %s for %s%s'):format(
        Shop.getPlayer(source).username, userId, itemId, item.price,
        giftedTo and (' as a gift for %s'):format(giftedTo) or ''
    ))

    return true
end

---@param itemId string
---@param creatorCode string?
---@return boolean success
---@return string? error
lib.callback.register('shop:server:purchaseItem', function(source, itemId, creatorCode)
    local ok, err = Shop.chargeAndRecord(source, itemId, creatorCode, nil)

    if not ok then
        return false, err
    end

    local granted, grantErr = core:GiveItem(source, itemId)

    if not granted then
        return false, grantErr or 'Could not grant the item.'
    end

    Shop.pushAll(source)

    return true
end)

---@return boolean success
---@return string? error
lib.callback.register('shop:server:refreshDailyStore', function(source)
    local price = Shop.tuning.dailyRefreshPrice

    if not core:RemoveCoins(source, price, 'shop:daily-refresh') then
        return false, 'You cannot afford a refresh.'
    end

    -- Reroll rather than advance: a fresh random seed, kept against today's
    -- day key so tomorrow still rolls over on its own.
    Shop.set(source, Shop.keys.dailySeed, math.random(1, 2147483646))
    Shop.set(source, Shop.keys.dailyDay, currentStoreDay())

    Shop.pushStore(source)

    return true
end)

-- -------------------------------------------------------- identity changes --

---@param username string
---@return boolean success
---@return string? error
lib.callback.register('shop:server:checkUsername', function(source, username)
    if type(username) ~= 'string' then
        return false, 'Invalid username.'
    end

    if core:ContainsProfanity(username) then
        return false, 'That username is not allowed.'
    end

    local taken = MySQL.scalar.await('SELECT 1 FROM users WHERE username = ? LIMIT 1', { username })

    if taken then
        return false, 'That username is taken.'
    end

    return true
end)

---@param username string
---@return boolean success
---@return string? error
lib.callback.register('shop:server:purchaseUsernameChange', function(source, username)
    if type(username) ~= 'string' then
        return false, 'Invalid username.'
    end

    if core:ContainsProfanity(username) then
        return false, 'That username is not allowed.'
    end

    if MySQL.scalar.await('SELECT 1 FROM users WHERE username = ? LIMIT 1', { username }) then
        return false, 'That username is taken.'
    end

    -- Charged before the rename so a rename that fails validation inside core
    -- cannot leave the player paid-up with the old name; the refund below is
    -- what covers that case.
    if not core:RemoveCoins(source, Shop.config.usernameChangeCost, 'shop:username-change') then
        return false, 'You cannot afford that.'
    end

    local ok, err = core:SetUsername(source, username)

    if not ok then
        core:AddCoins(source, Shop.config.usernameChangeCost, 'shop:username-change-refund')

        return false, err or 'Could not change your username.'
    end

    Shop.log(('%s changed their username to %s'):format(Shop.getUserId(source), username))

    return true
end)

---@param plate string
---@return boolean success
---@return string? error
local function validatePlate(plate)
    if type(plate) ~= 'string' then
        return false, 'Invalid plate.'
    end

    local trimmed = plate:gsub('^%s+', ''):gsub('%s+$', ''):upper()

    if #trimmed < Shop.config.plateMinLength or #trimmed > Shop.config.plateMaxLength then
        return false, ('A plate must be %s to %s characters.'):format(
            Shop.config.plateMinLength, Shop.config.plateMaxLength
        )
    end

    if trimmed:find('[^A-Z0-9 ]') then
        return false, 'A plate can only contain letters, numbers and spaces.'
    end

    if core:ContainsProfanity(trimmed) then
        return false, 'That plate is not allowed.'
    end

    return true, trimmed
end

---@param plate string
---@return boolean success
---@return string? error
lib.callback.register('shop:server:checkPlate', function(_, plate)
    local ok, result = validatePlate(plate)

    return ok, ok and nil or result
end)

---@param plate string
---@return boolean success
---@return string? error
lib.callback.register('shop:server:purchasePlateChange', function(source, plate)
    local ok, result = validatePlate(plate)

    if not ok then
        return false, result
    end

    if not core:RemoveCoins(source, Shop.config.plateChangeCost, 'shop:plate-change') then
        return false, 'You cannot afford that.'
    end

    Shop.set(source, 'custom_plate', result)
    Shop.pushAll(source)

    return true
end)

-- --------------------------------------------------------------- test gun --

---Try-before-you-buy. The weapon is handed over for the session only -- it is
---never written to the inventory -- and the player is moved to the range so
---they are not firing it at anyone.
---@param itemId string
---@return boolean success
---@return string? error
lib.callback.register('shop:server:enterTestGun', function(source, itemId)
    local item = Shop.getItem(itemId)

    if not item or item.category ~= 'weapons' then
        return false, 'That is not a weapon.'
    end

    if not item.baseWeapon then
        return false, 'That weapon cannot be tested.'
    end

    core:TeleportPlayer(source, Shop.tuning.testGun.coords)
    core:GiveWeapon(source, item.baseWeapon, Shop.tuning.testGun.ammo)

    return true
end)
