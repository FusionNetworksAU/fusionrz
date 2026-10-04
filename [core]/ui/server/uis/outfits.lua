---Saved outfits (pause menu > Profile > Outfits).
---
---ui/client/uis/outfits.lua has always called these five callbacks and
---nothing registered them, so opening the outfits tab raised "callback
---'pausemenu:server:fetchOutfits' does not exist" and saving one failed.
---
---Outfits get a table of their own rather than a key in core's metadata
---blob: metadata is replicated to the client on every write, and each outfit
---carries a full component / prop / tattoo list. The extra slot count is the
---exception -- it is tiny, the client already reads it from metadata
---(sharedConfig.getMaxOutfits), so it stays there.

local sharedConfig = require 'config.shared' ---@type UISharedConfig

local core = exports.core

local MAX_LABEL_LENGTH = 32
local MAX_APPEARANCE_BYTES = 32 * 1024
local MAX_CARD_IMAGES = 5

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `user_outfits` (
            `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `user_id`     INT UNSIGNED NOT NULL,
            `label`       VARCHAR(32)  NOT NULL,
            `model`       VARCHAR(64)  DEFAULT NULL,
            `appearance`  LONGTEXT     NOT NULL,
            `item_images` TEXT         NOT NULL,
            `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_user_outfits_user` (`user_id`)
        )
    ]])
end)

---@param source number
---@return table?
local function getPlayerData(source)
    return core:GetPlayerData(source)
end

---@param row table
---@return table
local function toSummary(row)
    local images = row.item_images and json.decode(row.item_images)

    return {
        outfitId = row.id,
        label = row.label,
        model = row.model,
        itemImages = type(images) == 'table' and images or {},
    }
end

---Card art: the shop clothing the player has on right now, by catalogue image.
---@param source number
---@return string[]
local function getEquippedClothingImages(source)
    local images = {}
    local ok, equipped = pcall(function()
        return exports.shop:GetEquippedItem(source, 'clothing')
    end)

    if not ok or type(equipped) ~= 'table' then
        return images
    end

    for _, itemId in pairs(equipped) do
        local item = core:GetItem(itemId)

        if item and type(item.image) == 'string' and item.image ~= '' then
            images[#images + 1] = item.image

            if #images >= MAX_CARD_IMAGES then
                break
            end
        end
    end

    return images
end

---@param outfit any
---@return table? appearance
---@return string? error
local function sanitiseOutfit(outfit)
    if type(outfit) ~= 'table' then
        return nil, 'Invalid outfit.'
    end

    local appearance = {
        components = type(outfit.components) == 'table' and outfit.components or {},
        props = type(outfit.props) == 'table' and outfit.props or {},
        tattoos = type(outfit.tattoos) == 'table' and outfit.tattoos or {},
    }

    if not next(appearance.components) and not next(appearance.props) then
        return nil, 'There is nothing to save.'
    end

    return appearance
end

---@return UserOutfitSummary[]
lib.callback.register('pausemenu:server:fetchOutfits', function(source)
    local player = getPlayerData(source)

    if not player then
        return {}
    end

    local rows = MySQL.query.await(
        'SELECT id, label, model, item_images FROM user_outfits WHERE user_id = ? ORDER BY id',
        { player.userId }
    ) or {}

    local outfits = {}

    for index = 1, #rows do
        outfits[index] = toSummary(rows[index])
    end

    return outfits
end)

---@param label string
---@param outfit { model: string?, components: table, props: table, tattoos: table }
---@return UserOutfitSummary|false
---@return string? error
lib.callback.register('pausemenu:server:createOutfit', function(source, label, outfit)
    local player = getPlayerData(source)

    if not player then
        return false, 'No player loaded.'
    end

    label = type(label) == 'string' and label:gsub('[^%w ]', ''):gsub('^%s+', ''):gsub('%s+$', '') or ''

    if label == '' then
        return false, 'Give your outfit a name.'
    end

    if #label > MAX_LABEL_LENGTH then
        return false, ('Outfit names must be at most %s characters.'):format(MAX_LABEL_LENGTH)
    end

    if core:ContainsProfanity(label) then
        return false, 'That outfit name contains profanities.'
    end

    local appearance, err = sanitiseOutfit(outfit)

    if not appearance then
        return false, err
    end

    local encoded = json.encode(appearance)

    if #encoded > MAX_APPEARANCE_BYTES then
        return false, 'That outfit is too large to save.'
    end

    local count = MySQL.scalar.await('SELECT COUNT(*) FROM user_outfits WHERE user_id = ?', { player.userId }) or 0
    local maxOutfits = sharedConfig.getMaxOutfits(player.metadata or {})

    if count >= maxOutfits then
        return false, ('You can only save %s outfits. Buy another slot to save more.'):format(maxOutfits)
    end

    local model = type(outfit.model) == 'string' and outfit.model:sub(1, 64) or nil
    local images = getEquippedClothingImages(source)

    local id = MySQL.insert.await(
        'INSERT INTO user_outfits (user_id, label, model, appearance, item_images) VALUES (?, ?, ?, ?, ?)',
        { player.userId, label, model, encoded, json.encode(images) }
    )

    if not id then
        return false, 'Could not save the outfit.'
    end

    return {
        outfitId = id,
        label = label,
        model = model,
        itemImages = images,
    }
end)

---@param outfitId number
---@return table|false outfit { model, components, props, tattoos }
---@return string? error
lib.callback.register('pausemenu:server:equipOutfitId', function(source, outfitId)
    local player = getPlayerData(source)
    local id = tonumber(outfitId)

    if not player or not id then
        return false, 'Invalid outfit.'
    end

    local row = MySQL.single.await(
        'SELECT model, appearance FROM user_outfits WHERE id = ? AND user_id = ?',
        { id, player.userId }
    )

    if not row then
        return false, 'That outfit no longer exists.'
    end

    local appearance = json.decode(row.appearance)

    if type(appearance) ~= 'table' then
        return false, 'That outfit could not be read.'
    end

    return {
        model = row.model,
        components = appearance.components or {},
        props = appearance.props or {},
        tattoos = appearance.tattoos or {},
    }
end)

---@param outfitId number
---@return boolean
---@return string? error
lib.callback.register('pausemenu:server:deleteOutfitId', function(source, outfitId)
    local player = getPlayerData(source)
    local id = tonumber(outfitId)

    if not player or not id then
        return false, 'Invalid outfit.'
    end

    local affected = MySQL.update.await('DELETE FROM user_outfits WHERE id = ? AND user_id = ?', { id, player.userId })

    if not affected or affected < 1 then
        return false, 'That outfit no longer exists.'
    end

    return true
end)

---@type table<number, true>
local purchasing = {}

---@return boolean
---@return string? error
lib.callback.register('pausemenu:server:purchaseOutfitSlot', function(source)
    if purchasing[source] then
        return false, 'Purchase already in progress.'
    end

    purchasing[source] = true

    local ok, success, err = pcall(function()
        local price = sharedConfig.outfitSlotPrice

        if core:GetCoins(source) < price then
            return false, ('You need %s coins to buy an outfit slot.'):format(price)
        end

        if not core:RemoveCoins(source, price, 'outfit slot') then
            return false, 'Could not take payment.'
        end

        local key = sharedConfig.outfitSlotMetadataKey
        local current = tonumber(core:GetMetadata(source, key)) or 0

        core:SetMetadata(source, key, current + 1)

        return true
    end)

    purchasing[source] = nil

    if not ok then
        lib.print.error(('[ui] outfit slot purchase failed for %s: %s'):format(source, success))

        return false, 'Something went wrong.'
    end

    return success, err
end)

AddEventHandler('playerDropped', function()
    purchasing[source] = nil
end)
