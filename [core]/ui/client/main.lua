local locations = require '@core.data.locations'
local locationCategories = require '@core.data.location-categories'

local core = exports.core

local playerState = LocalPlayer.state

playerState:set('uisReady', false, false)

---@type table<string, boolean>?
local aceAllowed

---@type table<string, string>
local itemAces = {}

---@type table<string, true>
local weaponAceItemIds = {}

local itemAcesBuilt = false

local function buildItemAces()
    itemAces = {}
    weaponAceItemIds = {}

    for weaponName, weaponData in pairs(core:GetWeaponsWithAce()) do
        local ace = weaponData.ace --[[@as string]]
        local dotIndex = ace:find('.', 1, true)

        if dotIndex then
            local itemId = ace:sub(dotIndex + 1)
            local itemData = core:GetItem(itemId)

            if itemData and itemData.ace == ace then
                itemAces[weaponName] = itemId
                weaponAceItemIds[itemId] = true
            end
        end
    end

    itemAcesBuilt = true
end

local function computeGlobalWeapons()
    if not aceAllowed or not itemAcesBuilt then
        return
    end

    ---@type table<string, true>
    local usableTypeIds = {}
    for _, typeId in pairs(core:GetUsableTypeIds()) do
        usableTypeIds[typeId] = true
    end

    ---@type table[]
    local list = {}

    for weaponName, weapon in pairs(core:GetWeapons()) do
        local allowed
        if not weapon.ace then
            allowed = true
        else
            local itemId = itemAces[weaponName]
            if itemId then
                allowed = usableTypeIds[itemId] == true
            else
                allowed = aceAllowed[weaponName] == true
            end
        end

        if allowed then
            list[#list + 1] = {
                name = weaponName,
                label = weapon.label,
                type = weapon.type,
                hasAce = not not weapon.ace,
            }
        end
    end

    SendNUIMessage({ action = 'setGlobalWeapons', data = list })
end

local function fetchAndSetGlobalWeapons()
    aceAllowed = lib.callback.await('ui:server:getGlobalWeaponAces', false)

    while not core:AreItemsReady() do
        Wait(50)
    end

    if not itemAcesBuilt then
        buildItemAces()
    end

    computeGlobalWeapons()
end

---@param affectedTypeIds string[]?
AddEventHandler('core:onInventoryUpdated', function(affectedTypeIds)
    if not aceAllowed then
        return
    end

    if affectedTypeIds then
        local relevant = false

        for i = 1, #affectedTypeIds do
            if weaponAceItemIds[affectedTypeIds[i]] then
                relevant = true
                break
            end
        end

        if not relevant then
            return
        end
    end

    computeGlobalWeapons()
end)

local uiHasCrashed = false

---Whether this page load has already been initialised. A plain local, not the
---uisReady statebag: a client-side statebag write goes via the server, so it
---does not read back true straight away, and every render in that window got
---past the guard and re-sent the data (665 "UI initialized" in one session).
local pageInitialised = false

local function pushInitialData()
    local teleportsData = {}
    for k, v in pairs(locations) do
        teleportsData[#teleportsData + 1] = {
            isFavorite = GetResourceKvpInt(('fusionrz:teleport_favorited:%s'):format(k)) == 1,
            players = 0,
            description = v.description,
            category = v.category,
            label = v.label,
            image = v.image,
            id = k
        }
    end

    SendNUIMessage({ action = 'setGlobalTeleportCategories', data = locationCategories })
    SendNUIMessage({ action = 'setGlobalTeleports', data = teleportsData })

    fetchAndSetGlobalWeapons()

    while not playerState.isLoaded do
        Wait(100)
    end

    SendNUIMessage({
        action = 'setUserData',
        data = {
            username = PlayerData.username,
            avatar = PlayerData.avatar,
            userId = PlayerData.userId
        }
    })

    SendNUIMessage({ action = 'setUserCoins', data = PlayerData.coins })

    SendNUIMessage({
        action = 'setSeason',
        data = {
            season = GetConvarInt('season', 0),
            endTimestamp = 0
        }
    })

    SendNUIMessage({ action = 'setPlayerLoaded', data = true })
end

RegisterNUICallback('init', function(_, cb)
    cb(1)

    -- The page calls `init` on every render of its root component, not once.
    -- Only the first after a load (or after uiCrashed cleared uisReady) may do
    -- anything: re-sending the data on every call re-rendered the page, which
    -- called init again, and the loop flooded the bridge ("Failed to fetch").
    if pageInitialised then
        return
    end

    pageInitialised = true

    local reinit = uiHasCrashed

    -- Local (non-replicated) write, so readers on this client see it at once.
    playerState:set('uisReady', true, false)
    TriggerEvent('uis:onReady')

    CreateThread(pushInitialData)

    lib.print.info(reinit and 'UI reloaded after a crash' or 'UI initialized')
end)

local function releaseUiFocus()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    TriggerScreenblurFadeOut(0)

    pcall(function() exports.ui:closeRankedMenu() end)
    pcall(function() exports.ui:closeMenu() end)
    pcall(function() exports.ui:setMatchAcceptVisible(false) end)
    pcall(function() exports.ui:setMapBanVisible(false) end)
end

---@param data { message: string?, reloading: boolean? }
RegisterNUICallback('uiCrashed', function(data, cb)
    cb(1)

    uiHasCrashed = true
    -- The reloaded page will call init again; let that one through.
    pageInitialised = false
    playerState:set('uisReady', false, false)

    releaseUiFocus()

    lib.print.error(('[ui] the interface crashed%s:\n%s'):format(
        data and data.reloading and ' and is reloading' or ' (reload limit hit, reconnect to restore it)',
        data and data.message or 'no details'
    ))

    exports.ui:notify({
        type = 'error',
        text = 'The interface hit an error and was reset. If something is missing, reconnect.',
        duration = 6000,
    })
end)

RegisterCommand('fixui', function()
    releaseUiFocus()

    lib.print.info('[ui] focus released by /fixui')
end, false)

---@param data table
RegisterNetEvent('core:onCoinsChange', function(data)
    SendNUIMessage({ action = 'setUserCoins', data = data.newAmount })
end)

RegisterNetEvent('ui:forceRefreshGlobalWeapons', function()
    fetchAndSetGlobalWeapons()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        playerState:set('uisReady', false, false)
    end
end)

---@param itemId string
AddEventHandler('core:onItemDeletedById', function(itemId)
    SendNUIMessage({
        action = 'deleteItemById',
        data = itemId
    })

    if not weaponAceItemIds[itemId] then
        return
    end

    weaponAceItemIds[itemId] = nil

    for weaponName, mappedItemId in pairs(itemAces) do
        if mappedItemId == itemId then
            itemAces[weaponName] = nil
        end
    end

    computeGlobalWeapons()
end)