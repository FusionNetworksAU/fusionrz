local playerState = LocalPlayer.state
local isPauseVisible = false

local isProfileDisabled = false
local isWorldMapDisabled = false
local isPauseMenuDisabled = false

local shop = exports.shop
local appearance = exports.appearance
local core = exports.core

local function canAccessMenu()
    if not playerState.uisReady
    or not playerState.isLoaded
    or playerState.isDead
    or lib.progressActive()
    or IsNuiFocused()
    or IsPauseMenuActive() then
        return false
    end

    return true
end

local function openWorldMap()
    ActivateFrontendMenu(`FE_MENU_VERSION_MP_PAUSE`, true, -1)

    Wait(20)
    PauseMenuceptionGoDeeper(1000)
end

---@param isVisible boolean
local function openPauseMenu(isVisible)
    SendNUIMessage({ action = 'setPauseMenuVisible', data = isVisible })
    SetNuiFocus(isVisible, isVisible)

    if isVisible then
        TriggerScreenblurFadeIn(0)
        TriggerEvent('ui:pauseMenuOpened')
    else
        TriggerScreenblurFadeOut(0)
        shop:stopPreview(true)
    end

    isPauseVisible = isVisible

    SetHudHiddenByMenu('pause', isVisible)

    RefreshMinimapRadarVisibility()
end

exports('openPauseMenu', openPauseMenu)

---@param cb function
---@return boolean
function CanUsePauseOrRankedMenu(cb)
    if isPauseVisible or IsRankedMenuVisible() or IsMenuVisible() then
        return true
    end

    cb(false)

    return false
end

RegisterNUICallback('openMap', function(_, cb)
    cb(1)
    if isPauseVisible and not isWorldMapDisabled then
        openPauseMenu(false)
        openWorldMap()
    end
end)

RegisterNUICallback('returnSpawnpoint', function(_, cb)
    cb(1)
    if isPauseVisible then
        openPauseMenu(false)
        ExecuteCommand('leave')
    end
end)

RegisterNUICallback('openSettings', function(_, cb)
    cb(1)
    if isPauseVisible then
        openPauseMenu(false)
        ActivateFrontendMenu(`FE_MENU_VERSION_LANDING_MENU`, false, -1)
    end
end)

RegisterNUICallback('exitPauseMenu', function(_, cb)
    cb(1)
    if isPauseVisible then
        openPauseMenu(false)
    end
end)

local keybind = lib.addKeybind({
    name = 'esc',
    description = 'Open Pause Menu',
    defaultKey = 'ESCAPE',
    onPressed = function()
        if GetResourceState('gamemodes') == 'started' and exports.gamemodes:isInDeathmatchQueue() then
            if exports.ui:isMatchAcceptVisible() or exports.ui:isMapBanVisible() or exports.ui:isReturnToLobbyVisible() then
                return
            end

            exports.ui:setReturnToLobbyVisible(true)
            return
        end

        if not canAccessMenu() then
            return
        end

        openPauseMenu(true)
    end
})

local mapKeybind = lib.addKeybind({
    name = 'worldmap',
    description = 'Open World Map',
    defaultKey = 'P',
    onPressed = function()
        if GetResourceState('gamemodes') == 'started' and exports.gamemodes:isInDeathmatchQueue() then
            return
        end

        if not canAccessMenu() then
            return
        end

        openWorldMap()
    end
})

---@param toggle boolean
exports('disablePauseMenu', function(toggle)
    isPauseMenuDisabled = toggle
    keybind:disable(toggle)
    mapKeybind:disable(isPauseMenuDisabled or isWorldMapDisabled)
end)

---@param disabled boolean gates the P keybind and the pause menu Map tab, ESC itself stays usable
exports('disableWorldMap', function(disabled)
    isWorldMapDisabled = disabled
    mapKeybind:disable(isPauseMenuDisabled or isWorldMapDisabled)
end)

---@param disabled boolean
exports('disablePauseMenuReturn', function(disabled)
    SendNUIMessage({ action = 'setPauseMenuDisableReturn', data = disabled })
end)

---@param disabled boolean
exports('setPauseMenuDisablePreview', function(disabled)
    SendNUIMessage({ action = 'setPauseMenuDisablePreview', data = disabled })
end)

---@param disabled boolean
exports('setPauseMenuDisableProfile', function(disabled)
    SendNUIMessage({ action = 'setPauseMenuDisableProfile', data = disabled })
    isProfileDisabled = disabled
end)

exports('isPauseMenuProfileDisabled', function()
    return isProfileDisabled
end)

local frontendAllowed = false

--- Stands the DisableFrontendThisFrame loop down while a script owns the frontend
---@param allowed boolean
function SetFrontendAllowed(allowed)
    frontendAllowed = allowed
end

CreateThread(function()
    while true do
        if not frontendAllowed then
            DisableFrontendThisFrame()
        end

        Wait(0)
    end
end)

---@param timestamp integer
exports('setShopFeaturedRefreshTimestamp', function(timestamp)
    SendNUIMessage({ action = 'setShopFeaturedRefreshTimestamp', data = timestamp })
end)

---@param timestamp integer
exports('setShopDailyRefreshTimestamp', function(timestamp)
    SendNUIMessage({ action = 'setShopDailyRefreshTimestamp', data = timestamp })
end)

---@param cost integer
exports('setShopDailyRefreshCount', function(cost)
    SendNUIMessage({ action = 'setShopDailyRefreshCount', data = cost })
end)

---@param categories table
exports('setShopDailyItems', function(categories)
    SendNUIMessage({ action = 'setShopDailyItems', data = categories })
end)

---@param items table
exports('setShopFeaturedItems', function(items)
    SendNUIMessage({ action = 'setShopFeaturedItems', data = items })
end)

---@param timestamp integer
exports('setShopEventEndTimestamp', function(timestamp)
    SendNUIMessage({ action = 'setShopEventEndTimestamp', data = timestamp })
end)

---@param items table
exports('setShopEventItems', function(items)
    SendNUIMessage({ action = 'setShopEventItems', data = items })
end)

---@param timestamp integer
exports('setShopEventAltEndTimestamp', function(timestamp)
    SendNUIMessage({ action = 'setShopEventAltEndTimestamp', data = timestamp })
end)

---@param items table
exports('setShopEventAltItems', function(items)
    SendNUIMessage({ action = 'setShopEventAltItems', data = items })
end)

---@param data table
---@param cb function
RegisterNUICallback('requestProfileSkins', function(data, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local weaponSkins, favorited = shop:GetSkinsForWeapon(data.weaponName)
    SendNUIMessage({
        action = 'setWeaponSkins',
        data = weaponSkins,
    })

    SendNUIMessage({ action = 'setFavoritedSkins', data = favorited })

    shop:previewWeaponSkin(data.weaponName, data.equippedSkinId)

    cb(true)
end)

---@param skins table
exports('setSkinsWeapons', function(skins)
    SendNUIMessage({ action = 'setSkinsWeapons', data = skins })
end)

---@param skins table
exports('setEquippedSkins', function(skins)
    SendNUIMessage({ action = 'setEquippedSkins', data = skins })
end)

---@param data table
---@param cb function
RegisterNUICallback('equipProfileSkin', function(data, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local success = lib.callback.await('shop:server:equipProfileSkin', false, data.categoryKey, data.weaponName, data.skinId)
    if success then
        shop:previewWeaponSkin(data.weaponName, data.skinId)
    end

    cb(success)
end)

---@param data table
---@param cb function
RegisterNUICallback('setFavoriteSkin', function(data, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local success = lib.callback.await('shop:server:setFavoriteSkin', false, data.baseSkinId, data.skinId, data.enabled)
    cb(success)
end)

---@param data { itemId: string, creatorCode: string? }
---@param cb function
RegisterNUICallback('purchaseShopItem', function(data, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local success, err = lib.callback.await('shop:server:purchaseItem', false, data.itemId, data.creatorCode)

    if not success then
        exports.ui:notify({ type = 'error', text = err or 'Something went wrong' })
    end

    cb(success)
end)

---@param _ any
---@param cb function
RegisterNUICallback('refreshDailyShop', function(_, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local success, err = lib.callback.await('shop:server:refreshDailyStore', false)

    if not success then
        exports.ui:notify({ type = 'error', text = err or 'Something went wrong' })
    end

    cb(success)
end)

---@param username string
---@param cb function
RegisterNUICallback('checkStoreUsername', function(username, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local success, err = lib.callback.await('shop:server:checkUsername', false, username)
    cb({ success = success, error = err })
end)

---@param username string
---@param cb function
RegisterNUICallback('purchaseUsernameChange', function(username, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local success, err = lib.callback.await('shop:server:purchaseUsernameChange', false, username)
    cb({ success = success, error = err })
end)

---@param plate string
---@param cb function
RegisterNUICallback('checkStorePlate', function(plate, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local success, err = lib.callback.await('shop:server:checkPlate', false, plate)
    cb({ success = success, error = err })
end)

---@param plate string
---@param cb function
RegisterNUICallback('purchasePlateChange', function(plate, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local success, err = lib.callback.await('shop:server:purchasePlateChange', false, plate)
    cb({ success = success, error = err })
end)

---@param items string[]
exports('setPurchasedShopItems', function(items)
    SendNUIMessage({ action = 'setPurchasedShopItems', data = items })
end)

---@param previewType ShopPreviewType
---@param cb function
RegisterNUICallback('startPreview', function(previewType, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    shop:startPreview(previewType)
    cb(true)
end)

---@param cb function
RegisterNUICallback('stopPreview', function(_, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    shop:stopPreview(false)

    if IsMenuVisible() then
        TriggerScreenblurFadeIn(0)
    end

    cb(true)
end)

function IsPauseMenuVisible()
    return isPauseVisible
end

exports('isPauseMenuVisible', IsPauseMenuVisible)

---@param itemId string?
---@param cb function
RegisterNUICallback('setShopPreview', function(itemId, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    if itemId then
        shop:previewShopItem(itemId)
    end

    cb(true)
end)

---@param changeAmount integer
---@param cb function
RegisterNUICallback('rotatePreviewEntity', function(changeAmount, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    shop:rotatePreviewEntity(changeAmount)
    cb(true)
end)

---@param changeAmount integer
---@param cb function
RegisterNUICallback('rollPreviewEntity', function(changeAmount, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    shop:rollPreviewEntity(changeAmount)
    cb(true)
end)

---@param notches number
---@param cb function
RegisterNUICallback('zoomPreviewEntity', function(notches, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    shop:zoomPreviewEntity(notches)
    cb(true)
end)

---@param data { dx: number, dy: number }
---@param cb function
RegisterNUICallback('panPreviewEntity', function(data, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    shop:panPreviewEntity(data.dx, data.dy)
    cb(true)
end)

---@param _ any
---@param cb function
RegisterNUICallback('resetPreviewView', function(_, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    shop:resetPreviewView()
    cb(true)
end)

---@param items table[]
exports('setOwnedClothingItems', function(items)
    SendNUIMessage({ action = 'setOwnedClothingItems', data = items })
end)

---@param items [string, string][]
exports('setEquippedClothing', function(items)
    SendNUIMessage({ action = 'setEquippedClothing', data = items })
end)

---@param items table[]
exports('setOwnedTattooItems', function(items)
    SendNUIMessage({ action = 'setOwnedTattooItems', data = items })
end)

---@param items [string, string][]
exports('setEquippedTattoos', function(items)
    SendNUIMessage({ action = 'setEquippedTattoos', data = items })
end)

---@param data table
---@param cb function
RegisterNUICallback('equipProfileTattoo', function(data, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local success = shop:equipTattoo(data.category, data.tattooId, data.equip)
    if success then
        local outfit = appearance:getPedAppearance(cache.ped)
        core:UpdatePlayerAppearance(outfit)
    end
    cb(success)
end)

---@param data table
---@param cb function
RegisterNUICallback('equipProfileClothing', function(data, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local success = shop:equipClothing(data.category, data.clothingId)
    if success then
        local outfit = appearance:getPedAppearance(cache.ped)
        core:UpdatePlayerAppearance(outfit)
    end
    cb(success)
end)

---@param itemId string
---@param cb function
RegisterNUICallback('previewStoreAudio', function(itemId, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local success = shop:previewStoreAudio(itemId)
    cb(success)
end)

RegisterNUICallback('switchPreviewGender', function(_, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local success = shop:switchPreviewGender()
    cb(success)
end)

---@param data table
---@param cb function
RegisterNUICallback('equipProfileSound', function(data, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local success = shop:equipSoundId(data.soundId)
    cb(success)
end)

---@param ownedSounds table[]
exports('setOwnedSounds', function(ownedSounds)
    SendNUIMessage({ action = 'setOwnedSounds', data = ownedSounds })
end)

---@param soundId string?
exports('setEquippedSoundId', function(soundId)
    SendNUIMessage({ action = 'setEquippedSoundId', data = soundId })
end)

---@param backgroundId string
---@param cb function
RegisterNUICallback('equipBackground', function(backgroundId, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local success = shop:equipBackgroundId(backgroundId)
    cb(success)
end)

---@param plateId string
---@param cb function
RegisterNUICallback('equipPlate', function(plateId, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local success = shop:equipPlateId(plateId)
    cb(success)
end)

---@param plates table[]
exports('setPlates', function(plates)
    SendNUIMessage({ action = 'setPlates', data = plates })
end)

---@param plateId string?
exports('setEquippedPlateId', function(plateId)
    SendNUIMessage({ action = 'setEquippedPlateId', data = plateId })
end)

---@param backgrounds table[]
exports('setBackgrounds', function(backgrounds)
    SendNUIMessage({ action = 'setBackgrounds', data = backgrounds })
end)

---@param backgroundId string?
exports('setEquippedBackgroundId', function(backgroundId)
    SendNUIMessage({ action = 'setEquippedBackgroundId', data = backgroundId })
end)

---@param decorationId string
---@param cb function
RegisterNUICallback('equipDecoration', function(decorationId, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local success = shop:equipAvatarDecorationId(decorationId)
    cb(success)
end)

---@param decorations table[]
exports('setDecorations', function(decorations)
    SendNUIMessage({ action = 'setDecorations', data = decorations })
end)

---@param decorationId string?
exports('setEquippedDecorationId', function(decorationId)
    SendNUIMessage({ action = 'setEquippedDecorationId', data = decorationId })
end)

---@param ownedEmotes table[]
exports('setOwnedEmotes', function(ownedEmotes)
    SendNUIMessage({ action = 'setOwnedEmotes', data = ownedEmotes })
end)

---@param slots table<string, string>
exports('setEquippedEmoteSlots', function(slots)
    SendNUIMessage({ action = 'setEquippedEmoteSlots', data = slots })
end)

---@param count integer
exports('setEmoteSlotCount', function(count)
    SendNUIMessage({ action = 'setEmoteSlotCount', data = count })
end)

---@param data { slotIndex: integer, emoteId: string? }
---@param cb function
RegisterNUICallback('equipEmoteSlot', function(data, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local success = shop:equipEmoteSlot(data.slotIndex, data.emoteId)
    cb(success)
end)

---@param gifts ReceivedGift[]
exports('setReceivedGifts', function(gifts)
    SendNUIMessage({ action = 'setReceivedGifts', data = gifts })
end)

---@param gift ReceivedGift
exports('addReceivedGift', function(gift)
    SendNUIMessage({ action = 'addReceivedGift', data = gift })
end)

---@param giftId integer
exports('removeReceivedGift', function(giftId)
    SendNUIMessage({ action = 'removeReceivedGift', data = giftId })
end)

---@param data { giftId: integer }
---@param cb function
RegisterNUICallback('acceptGift', function(data, cb)
    cb(true)
end)

---@param data { itemId: string, targetUserId: integer, creatorCode: string? }
---@param cb function
RegisterNUICallback('giftShopItem', function(data, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local success, err = lib.callback.await('shop:server:giftItem', false, data.itemId, data.targetUserId, data.creatorCode)

    if not success then
        exports.ui:notify({ type = 'error', text = err or 'Something went wrong' })
    else
        exports.ui:notify({ type = 'success', text = 'Gift sent successfully' })
    end

    cb(success)
end)

---@param data { giftId: integer }
---@param cb function
RegisterNUICallback('claimGift', function(data, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local success, err = shop:claimGift(data.giftId)

    if not success then
        exports.ui:notify({ type = 'error', text = err or 'Something went wrong' })
    end

    cb(success)
end)

---@param data { giftId: integer, itemId: string, category: string }
---@param cb function
RegisterNUICallback('equipGiftItem', function(data, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    if data.giftId then
        local claimed, claimErr = shop:claimGift(data.giftId)
        if not claimed then
            exports.ui:notify({ type = 'error', text = claimErr or 'Failed to claim the gift' })
            cb(false)
            return
        end
    end

    local category = data.category
    local success = false

    if category == 'clothing' then
        shop:equipClothing(nil, data.itemId)
        local appearanceTable = appearance:getPedAppearance(cache.ped)
        core:UpdatePlayerAppearance(appearanceTable)
        success = true
    elseif category == 'outfits' then
        local linkedItems = lib.callback.await('shop:server:getOutfitLinkedItems', false, data.itemId)
        if linkedItems then
            for _, clothingId in ipairs(linkedItems) do
                shop:equipClothing(nil, clothingId)
            end
            local appearanceTable = appearance:getPedAppearance(cache.ped)
            core:UpdatePlayerAppearance(appearanceTable)
        end
        success = true
    elseif category == 'weapons' or category == 'livery' then
        success = true
    elseif category == 'sounds' then
        success = shop:equipSoundId(data.itemId)
    elseif category == 'backgrounds' then
        success = shop:equipBackgroundId(data.itemId)
    elseif category == 'plates' then
        success = shop:equipPlateId(data.itemId)
    elseif category == 'decorations' then
        success = shop:equipAvatarDecorationId(data.itemId)
    elseif category == 'chat_colors' then
        success = shop:equipChatColorId(data.itemId)
    else
        success = true
    end

    if not success then
        exports.ui:notify({ type = 'error', text = 'Failed to equip the item' })
    end

    cb(success)
end)

---@param numTokens integer
exports('setNumRefundTokens', function(numTokens)
    SendNUIMessage({ action = 'setNumRefundTokens', data = numTokens })
end)

---@param data table[]
exports('setRefundItems', function(data)
    SendNUIMessage({ action = 'setRefundItems', data = data })
end)

---@param cb function
RegisterNUICallback('refundsPageOpened', function(_, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    cb(shop:loadRefundableItems())
end)

RegisterNUICallback('refundStoreItem', function(itemId, cb)
    local success = shop:refundItem(itemId)
    cb(success)
end)

---@param code string
---@param cb function
RegisterNUICallback('trySetCreatorCode', function(code, cb)
    local valid, err = true, nil
    if #code > 0 then
        valid, err = lib.callback.await('shop:server:validateCreatorCode', false, code)
    end

    if valid then
        shop:setSavedCreatorCode(code)
        exports.ui:notify({ type = 'success', text = 'Creator code applied successfully.' })
    else
        exports.ui:notify({ type = 'error', text = err or 'Unknown error.' })
    end
    cb(valid)
end)

exports('setCreatorCode', function(creatorCode)
    SendNUIMessage({ action = 'setCreatorCode', data = creatorCode })
end)

---@type CreatorSelfInfo?
local cachedCreatorSelfInfo = nil

local function sendCreatorSelfInfo()
    SendNUIMessage({ action = 'setCreatorSelfInfo', data = cachedCreatorSelfInfo })
end

---@param selfInfo CreatorSelfInfo?
RegisterNetEvent('shop:setCreatorSelfInfo', function(selfInfo)
    cachedCreatorSelfInfo = selfInfo

    if playerState.uisReady then
        sendCreatorSelfInfo()
    end
end)

AddEventHandler('uis:onReady', function()
    if cachedCreatorSelfInfo then
        sendCreatorSelfInfo()
    end
end)

---@param cb function
RegisterNUICallback('creatorPageOpened', function(_, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    TriggerServerEvent('shop:server:refreshCreatorSelfInfo')
    cb(true)
end)

---@param data { timespan: CreatorTimespan }
---@param cb function
RegisterNUICallback('getCreatorTimespanStats', function(data, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local stats = lib.callback.await('shop:server:getCreatorTimespanStats', false, data.timespan) ---@type CreatorTimespanSupporters?
    cb(stats or false)
end)

---@param data { timespan: CreatorTimespan }
---@param cb function
RegisterNUICallback('getCreatorTimespanEarnings', function(data, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local points = lib.callback.await('shop:server:getCreatorTimespanEarnings', false, data.timespan) ---@type CreatorEarningsPoint[]?
    cb(points or false)
end)

---@param data { page: integer, timespan: CreatorTimespan }
---@param cb function
RegisterNUICallback('getCreatorTopSpenders', function(data, cb)
    if not CanUsePauseOrRankedMenu(cb) then
        return
    end

    local result = lib.callback.await('shop:server:getCreatorTopSpenders', false, data.page, data.timespan) ---@type CreatorTopSpendersPage?
    cb(result or false)
end)

RegisterNUICallback('enterTestGun', function(itemId, cb)
    local success, err = lib.callback.await('shop:server:enterTestGun', false, itemId)
    if not success then
        exports.ui:notify({ type = 'error', text = err or 'Unknown error.' })
    elseif IsMenuVisible() then
        exports.ui:closeMenu()
    end
    cb(success)
end)

---@param favoriteIds table<string, boolean>
exports('setFavoriteClothing', function(favoriteIds)
    SendNUIMessage({ action = 'setFavoriteClothing', data = favoriteIds })
end)

RegisterNUICallback('setFavoriteClothingSkin', function(data, cb)
    local success = lib.callback.await('shop:server:setFavoriteClothing', false, data.skinId, data.enabled)
    if not success then
        exports.ui:notify({ type = 'error', text = 'Failed to toggle favorite clothing.' })
    end
    cb(success)
end)

---@param options table
exports('setBodyOptions', function(options)
    SendNUIMessage({ action = 'setBodyOptions', data = options })
end)