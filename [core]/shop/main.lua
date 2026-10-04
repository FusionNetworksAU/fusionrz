---Shop client.
---
---One file, because the manifest declares one client script. It is in three
---parts: the profile snapshot and the equip exports, the store preview, and
---emotes. Every `shop:` export ui/client/uis/*.lua reaches for is here.
---
---Reads answer out of the snapshot; equips ask the server first and only
---then touch the local ped. Nothing grants an entitlement client-side -- the
---snapshot is a mirror of what the server said, refreshed when it says so.


local ui = exports.ui
local appearance = exports.appearance

---config/preview.lua is the camera's own tuning -- the same file the shop's
---preview lighting comes from -- so the zoom and pitch limits are read from
---there rather than restated here.
PreviewCam = require 'config.preview'

---The knobs the config files have no key for. Mirrors shared/shop.lua's
---`Shop.tuning`, which the server reads; the client cannot see that file
---because it is a server script, so the handful of values used on this side
---are repeated. Keep the two in step.
Tuning = {
    previewCoords = vec4(-3675.2393, -1055.2307, 1600.0, 180.0),
    maleModel = `mp_m_freemode_01`,
    femaleModel = `mp_f_freemode_01`,

    emotes = {
        defaultSlots = 8,
        blockInVehicle = true,
        blockWhileDead = true,
    },
}

---@type table? the last shop:server:getProfileData result
local profile = nil

---@return table
local function owned()
    return profile and profile.owned or {}
end

---@return table
local function equipped()
    return profile and profile.equipped or {}
end

exports('getProfile', function()
    return profile
end)

-- ---------------------------------------------------------------- fan out --

---Pushes the snapshot into the NUI through ui's `set*` exports. This is the
---only place that happens: the server never calls them, because they live on
---the client.
local function applyProfile()
    if not profile then
        return
    end

    local own = owned()
    local eq = equipped()

    ui:setOwnedClothingItems(own.clothing or {})
    ui:setOwnedTattooItems(own.tattoos or {})
    ui:setOwnedSounds(own.sounds or {})
    ui:setPlates(own.plates or {})
    ui:setBackgrounds(own.backgrounds or {})
    ui:setDecorations(own.decorations or {})
    ui:setOwnedEmotes(own.emotes or {})
    ui:setPurchasedShopItems(own.purchasedIds or {})

    ui:setEquippedClothing(eq.clothing or {})
    ui:setEquippedTattoos(eq.tattoos or {})
    ui:setEquippedSoundId(eq.soundId)
    ui:setEquippedPlateId(eq.plateId)
    ui:setEquippedBackgroundId(eq.backgroundId)
    ui:setEquippedDecorationId(eq.decorationId)
    ui:setEquippedSkins(eq.weaponSkins or {})
    ui:setFavoriteClothing(eq.favoriteClothing or {})
    ui:setEquippedEmoteSlots(eq.emoteSlots or {})
    ui:setEmoteSlotCount(eq.emoteSlotCount or Tuning.emotes.defaultSlots)

    ui:setCreatorCode(profile.creatorCode)
    ui:setNumRefundTokens(profile.refundTokens or 0)
end

local function refresh()
    profile = lib.callback.await('shop:server:getProfileData', false)

    applyProfile()
end


RegisterNetEvent('shop:client:refresh', function()
    CreateThread(refresh)
end)

RegisterNetEvent('shop:client:setStore', function(store)
    if type(store) ~= 'table' then
        return
    end

    local daily = store.daily

    if type(daily) ~= 'table'
        or type(daily.leftItems) ~= 'table'
        or type(daily.rightItems) ~= 'table'
        or (#daily.leftItems == 0 and #daily.rightItems == 0) then
        return
    end

    ui:setShopDailyItems({
        title = daily.title or '',
        leftItems = daily.leftItems,
        rightItems = daily.rightItems,
    })

    if type(store.featured) == 'table' and #store.featured > 0 then
        ui:setShopFeaturedItems(store.featured)
    end
end)

RegisterNetEvent('shop:client:setGifts', function(gifts)
    ui:setReceivedGifts(gifts or {})
end)

RegisterNetEvent('shop:client:addGift', function(gift)
    ui:addReceivedGift(gift)
end)

RegisterNetEvent('shop:client:removeGift', function(giftId)
    ui:removeReceivedGift(giftId)
end)

CreateThread(function()
    CoreClient.awaitPlayerLoaded()

    refresh()
end)

---@param itemId string?
---@return table?
local function getCatalogueItem(itemId)
    if not itemId then
        return nil
    end

    for _, list in pairs(owned()) do
        if type(list) == 'table' then
            for index = 1, #list do
                if list[index].itemId == itemId then
                    return list[index]
                end
            end
        end
    end

    return nil
end

---@param category string?
---@param clothingId string?
---@return boolean success
exports('equipClothing', function(category, clothingId)
    -- The server answers with the slot and what to put on (shared/clothing.lua),
    -- including for the per-slot "default" piece.
    local ok, _, apply = lib.callback.await('shop:server:equipClothing', false, {
        category = category,
        itemId = clothingId,
    })

    if not ok then
        return false
    end

    if type(apply) == 'table' then
        appearance:setPedComponents(cache.ped, apply.components)
        appearance:setPedProps(cache.ped, apply.props)

        -- Keep the menu's preview ped (if one is up) dressed the same.
        -- Tattoos are passed through unchanged: appearance keeps them in shared
        -- state, so an empty list here would drop the player's own.
        exports.shop:setPreviewPedAppearance({
            components = apply.components or {},
            props = apply.props or {},
            tattoos = appearance:getPedTattoos(cache.ped),
        })
    end

    return true
end)

---@param category string?
---@param tattooId string?
---@param equip boolean?
---@return boolean success
exports('equipTattoo', function(category, tattooId, equip)
    local ok = lib.callback.await('shop:server:equipTattoo', false, {
        category = category,
        itemId = tattooId,
        equip = equip,
    })

    if not ok then
        return false
    end

    local item = getCatalogueItem(tattooId)

    if item and item.collection and item.overlay then
        local data = { collection = item.collection, name = item.overlay }

        if equip == false then
            appearance:deleteTattoo(data)
        else
            appearance:applyTattoo(data)
        end
    end

    return true
end)

---@param soundId string?
---@return boolean success
exports('equipSoundId', function(soundId)
    return lib.callback.await('shop:server:equipSound', false, soundId) == true
end)

---@param backgroundId string?
---@return boolean success
exports('equipBackgroundId', function(backgroundId)
    return lib.callback.await('shop:server:equipBackground', false, backgroundId) == true
end)

---@param plateId string?
---@return boolean success
exports('equipPlateId', function(plateId)
    return lib.callback.await('shop:server:equipPlate', false, plateId) == true
end)

---@param decorationId string?
---@return boolean success
exports('equipAvatarDecorationId', function(decorationId)
    return lib.callback.await('shop:server:equipDecoration', false, decorationId) == true
end)

---@param colorId string?
---@return boolean success
exports('equipChatColorId', function(colorId)
    return lib.callback.await('shop:server:equipChatColor', false, colorId) == true
end)

---@return table[]
exports('getChatColorOptions', function()
    local own = owned()

    return own.chatColors or {}
end)

---@return string?
exports('getEquippedChatColorId', function()
    return equipped().chatColorId
end)

---@param weaponName string
---@return table[] skins
---@return table<string, boolean> favorited
exports('GetSkinsForWeapon', function(weaponName)
    local skins, favorited = lib.callback.await('shop:server:getSkinsForWeapon', false, weaponName)

    return skins or {}, favorited or {}
end)

---@return table[]
exports('loadRefundableItems', function()
    local result = lib.callback.await('shop:server:getRefundableItems', false) or {}

    ui:setNumRefundTokens(result.tokens or 0)
    ui:setRefundItems(result.items or {})

    return result.items or {}
end)

---@param itemId string
---@return boolean success
exports('refundItem', function(itemId)
    local ok, err = lib.callback.await('shop:server:refundItem', false, itemId)

    if not ok then
        ui:notify({ type = 'error', text = err or 'Could not refund that item.' })

        return false
    end

    return true
end)

---@param giftId integer
---@return boolean success
---@return string? error
exports('claimGift', function(giftId)
    return lib.callback.await('shop:server:claimGift', false, giftId)
end)

---@param code string?
exports('setSavedCreatorCode', function(code)
    local normalised = (type(code) == 'string' and #code > 0) and code or nil

    if profile then
        profile.creatorCode = normalised
    end

    ui:setCreatorCode(normalised)
    TriggerServerEvent('shop:server:setCreatorCode', normalised)
end)

---@type table<string, boolean>
local tattooTextureResults = {}

exports('setFetchTattooTextureResult', function(data)
    if type(data) ~= 'table' or type(data.textureName) ~= 'string' then
        return
    end

    tattooTextureResults[data.textureName] = data.exists == true
end)

---@param textureName string
---@return boolean?
exports('getFetchTattooTextureResult', function(textureName)
    return tattooTextureResults[textureName]
end)






---@alias ShopPreviewType 'ped' | 'weapon' | 'audio' | string

---@type integer? the preview ped
local previewPed = nil

---@type integer? the preview weapon object
local previewObject = nil

---@type integer? the scripted camera
local previewCam = nil

---@type ShopPreviewType?
local previewType = nil

local view = {
    yaw = 0.0,
    pitch = 0.0,
    zoom = 1.0,
    offsetX = 0.0,
    offsetZ = 0.0,
}

---@type boolean
local previewFemale = false

---Camera distance at zoom 1, and the height it aims at above the anchor.
local PREVIEW_DISTANCE = 3.4
local PREVIEW_AIM_HEIGHT = 0.8

local function resetView()
    view.yaw = 0.0
    view.pitch = 0.0
    view.zoom = 1.0
    view.offsetX = 0.0
    view.offsetZ = 0.0
end

---@param cam integer
---@param x number
---@param y number
---@param z number
local function pointAtCoord(cam, x, y, z)
    local coords = GetCamCoord(cam)
    local dx, dy, dz = x - coords.x, y - coords.y, z - coords.z
    local horizontal = math.sqrt(dx * dx + dy * dy)

    SetCamRot(cam, math.deg(math.atan(dz, horizontal)), 0.0, math.deg(-math.atan(dx, dy)), 2)
end

local function applyView()
    if not previewCam then
        return
    end

    local anchor = Tuning.previewCoords

    -- Far enough back, and aimed at mid-body, that the whole ped fits the
    -- frame head to shoes at the default zoom. It sat 2.2m away aimed at the
    -- hips, which showed only the legs and cut the head off.
    local distance = PREVIEW_DISTANCE / view.zoom
    local aimZ = anchor.z + PREVIEW_AIM_HEIGHT
    local yaw = math.rad(view.yaw)
    local pitch = math.rad(view.pitch)

    local horizontal = distance * math.cos(pitch)

    SetCamCoord(
        previewCam,
        anchor.x + math.sin(yaw) * horizontal + view.offsetX,
        anchor.y - math.cos(yaw) * horizontal,
        aimZ + distance * math.sin(pitch) + view.offsetZ
    )

    pointAtCoord(previewCam, anchor.x + view.offsetX, anchor.y, aimZ + view.offsetZ)
end

---@return integer
local function ensurePed()
    if previewPed and DoesEntityExist(previewPed) then
        return previewPed
    end

    local model = previewFemale and Tuning.femaleModel or Tuning.maleModel

    lib.requestModel(model, 10000)

    local anchor = Tuning.previewCoords

    -- The preview hangs far off the map; the game only streams and draws
    -- around its focus, which is why the ped sometimes never appeared.
    SetFocusPosAndVel(anchor.x, anchor.y, anchor.z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(anchor.x, anchor.y, anchor.z)

    previewPed = CreatePed(4, model, anchor.x, anchor.y, anchor.z, anchor.w, false, false)

    SetModelAsNoLongerNeeded(model)
    SetEntityInvincible(previewPed, true)
    SetBlockingOfNonTemporaryEvents(previewPed, true)
    FreezeEntityPosition(previewPed, true)
    SetEntityVisible(previewPed, true, false)
    SetEntityLodDist(previewPed, 0xFFFF)
    SetPedDefaultComponentVariation(previewPed)

    -- Dressed as the player -- face, hair and all, not just the clothes --
    -- when the preview is their own gender.
    local ok, own = pcall(function()
        return appearance:getPedAppearance(cache.ped)
    end)

    if ok and own and GetEntityModel(cache.ped) == model then
        pcall(function()
            appearance:setPedAppearance(previewPed, own)
        end)
    end

    return previewPed
end

local function destroyObject()
    if previewObject and DoesEntityExist(previewObject) then
        DeleteEntity(previewObject)
    end

    previewObject = nil
end

local function destroyPed()
    if previewPed and DoesEntityExist(previewPed) then
        DeleteEntity(previewPed)
    end

    previewPed = nil
end

---@param kind ShopPreviewType
exports('startPreview', function(kind)
    -- Opens on the player's own gender; the gender switch flips from there.
    if previewType == nil then
        previewFemale = GetEntityModel(cache.ped) == Tuning.femaleModel
    end

    previewType = kind

    resetView()

    if kind ~= 'weapon' then
        ensurePed()
    end

    if not previewCam then
        previewCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

        SetCamFov(previewCam, 40.0)
        SetCamActive(previewCam, true)
        RenderScriptCams(true, true, 400, true, true)
    end

    applyView()

    return true
end)

---@param immediate boolean?
exports('stopPreview', function(immediate)
    if previewCam then
        RenderScriptCams(false, not immediate, immediate and 0 or 400, true, true)
        DestroyCam(previewCam, false)

        previewCam = nil
    end

    destroyObject()
    destroyPed()

    -- Hand streaming back; the ranked lobby re-takes it on shop:previewStopped.
    ClearFocus()

    previewType = nil
    previewFemale = false

    resetView()

    -- RenderScriptCams(false) above hands the view to the gameplay camera,
    -- not to whichever scripted camera was showing before the preview. The
    -- ranked lobby listens for this to take its own camera back.
    TriggerEvent('shop:previewStopped')

    return true
end)

---@param changeAmount number
exports('rotatePreviewEntity', function(changeAmount)
    view.yaw = (view.yaw + (tonumber(changeAmount) or 0)) % 360.0

    applyView()

    return true
end)

---@param changeAmount number
exports('rollPreviewEntity', function(changeAmount)
    local pitch = view.pitch + (tonumber(changeAmount) or 0)

    view.pitch = math.min(PreviewCam.pitchLimit, math.max(-PreviewCam.pitchLimit, pitch))

    applyView()

    return true
end)

---@param notches number
exports('zoomPreviewEntity', function(notches)
    local zoom = view.zoom * (PreviewCam.zoomStep ^ (tonumber(notches) or 0))

    view.zoom = math.min(PreviewCam.zoomMax, math.max(PreviewCam.zoomMin, zoom))

    applyView()

    return true
end)

---@param dx number
---@param dy number
exports('panPreviewEntity', function(dx, dy)
    view.offsetX = view.offsetX + (tonumber(dx) or 0) * 0.01
    view.offsetZ = view.offsetZ - (tonumber(dy) or 0) * 0.01

    applyView()

    return true
end)

exports('resetPreviewView', function()
    resetView()
    applyView()

    return true
end)

---@return boolean success
exports('switchPreviewGender', function()
    previewFemale = not previewFemale

    destroyPed()
    ensurePed()

    return true
end)

---Puts an outfit on the preview ped without touching the player. Called by
---ui/client/uis/outfits.lua when an outfit is equipped, so the preview keeps
---up with the change.
---@param outfit table
exports('setPreviewPedAppearance', function(outfit)
    if not previewPed or not DoesEntityExist(previewPed) or type(outfit) ~= 'table' then
        return false
    end

    appearance:setPedComponents(previewPed, outfit.components)
    appearance:setPedProps(previewPed, outfit.props)
    appearance:setPedTattoos(previewPed, outfit.tattoos)

    return true
end)

---@param itemId string
---@return boolean success
exports('previewShopItem', function(itemId)
    -- A preview can be requested before startPreview -- clicking a store card
    -- opens the panel and asks for the preview in the same frame -- so the
    -- ped is made sure of here rather than assumed.
    local ped = ensurePed()

    local item = lib.callback.await('shop:server:getPreviewData', false, itemId)

    if not item then
        return false
    end

    if item.category == 'clothing' and item.component then
        SetPedComponentVariation(ped, item.component, item.drawable or 0, item.texture or 0, 0)
    elseif item.category == 'tattoos' and item.collection and item.overlay then
        appearance:setPedTattoos(ped, { { collection = item.collection, name = item.overlay } })
    elseif item.category == 'weapons' and item.baseWeapon then
        exports.shop:previewWeaponSkin(item.baseWeapon, itemId)
    end

    return true
end)

---Weapon skins are shown on a prop rather than on the ped: the ped would
---have to be given the weapon, which means arming a ped inside a menu.
---@param weaponName string
---@param skinId string?
---@return boolean success
exports('previewWeaponSkin', function(weaponName, skinId)
    destroyObject()

    if type(weaponName) ~= 'string' then
        return false
    end

    local model = joaat(('w_%s'):format(weaponName:lower():gsub('^weapon_', '')))

    if not IsModelInCdimage(model) or not IsModelValid(model) then
        -- No prop for this weapon: not an error, just nothing to show.
        return true
    end

    lib.requestModel(model, 5000)

    local anchor = Tuning.previewCoords

    previewObject = CreateObject(model, anchor.x, anchor.y, anchor.z + 0.9, false, false, false)

    SetModelAsNoLongerNeeded(model)
    FreezeEntityPosition(previewObject, true)
    SetEntityCollision(previewObject, false, false)

    return skinId ~= nil
end)

---@param itemId string
---@return boolean success
exports('previewStoreAudio', function(itemId)
    local sound = lib.callback.await('shop:server:getPreviewData', false, itemId)

    if not sound or sound.category ~= 'sounds' then
        return false
    end

    local name = sound.soundName or sound.data and sound.data.soundName
    local set = sound.soundSet or sound.data and sound.data.soundSet

    if not name then
        return false
    end

    PlaySoundFrontend(-1, name, set or 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)

    return true
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then
        return
    end

    if previewCam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(previewCam, false)
    end

    destroyObject()
    destroyPed()
end)





---@type integer? the animation dictionary currently playing
local playingUntil = nil

---@return table<string, string>
exports('getEquippedEmoteSlots', function()
    return equipped().emoteSlots or {}
end)

---@return integer
exports('getEmoteSlotCount', function()
    return equipped().emoteSlotCount or Tuning.emotes.defaultSlots
end)

---The wheel renders `emoteId`, `label` and `image` per entry, so the owned
---list is reshaped into that here rather than in the UI.
---@return table[]
exports('getOwnedEmotes', function()
    local list = owned().emotes or {}
    local entries = {}

    for index = 1, #list do
        entries[index] = {
            emoteId = list[index].itemId,
            label = list[index].label,
            image = list[index].image,
        }
    end

    return entries
end)

---@return boolean
local function canUseEmotes()
    if Tuning.emotes.blockWhileDead and IsEntityDead(cache.ped) then
        return false
    end

    if Tuning.emotes.blockInVehicle and IsPedInAnyVehicle(cache.ped, false) then
        return false
    end

    return true
end

exports('canUseEmotes', canUseEmotes)

local function stopEmote()
    playingUntil = nil

    ClearPedTasks(cache.ped)
end

---Emotes are cancelled by moving, the same as every other server: holding a
---dedicated key to stop dancing is worse than just walking away.
CreateThread(function()
    while true do
        if not playingUntil then
            Wait(250)
        else
            if GetGameTimer() > playingUntil
                or not canUseEmotes()
                or IsControlPressed(0, 32) or IsControlPressed(0, 33)
                or IsControlPressed(0, 34) or IsControlPressed(0, 35)
                or IsControlJustPressed(0, 22) then
                stopEmote()
            end

            Wait(0)
        end
    end
end)

---@param slotIndex integer
---@return boolean success
exports('playEmoteSlot', function(slotIndex)
    if not canUseEmotes() then
        return false
    end

    local slots = exports.shop:getEquippedEmoteSlots()
    local emoteId = slots[tostring(slotIndex)]

    if not emoteId then
        return false
    end

    local emote = lib.callback.await('shop:server:getPreviewData', false, emoteId)

    if not emote or emote.category ~= 'emotes' or not emote.dictionary or not emote.animation then
        return false
    end

    if not lib.requestAnimDict(emote.dictionary, 5000) then
        return false
    end

    -- Flag 49 is looping + upper-body-allowed + cancellable, which is what
    -- makes the movement check above able to break out of it.
    TaskPlayAnim(cache.ped, emote.dictionary, emote.animation, 4.0, -4.0, -1, 49, 0.0, false, false, false)

    RemoveAnimDict(emote.dictionary)

    playingUntil = GetGameTimer() + 60000

    return true
end)

exports('stopEmote', stopEmote)

---@param slotIndex integer
---@param emoteId string?
---@return boolean success
exports('equipEmoteSlot', function(slotIndex, emoteId)
    local ok = lib.callback.await('shop:server:equipEmoteSlot', false, slotIndex, emoteId)

    return ok == true
end)

---ui/client/uis/ranked.lua shows this next to the wheel so players know how
---to stop an emote. There is no bind of our own -- movement is the cancel --
---so the control it names is the one the loop above watches.
---@return string
exports('GetEmoteCancelKeyBind', function()
    return 'W'
end)

AddEventHandler('core:onPlayerUnloaded', stopEmote)
