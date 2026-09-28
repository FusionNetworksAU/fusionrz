local playerState = LocalPlayer.state
local ui = exports.ui
local WASTELAND_ACTIVITY = 'WASTELAND'
local cataloguePushed = false
local snapshotPushed = false
local isInventoryOpen = false
local inWasteland = false

---@type integer?
local openContainerInv = nil

---@type table?
local openContainerLayout = nil

local function pushCatalogue()
    if cataloguePushed or not inWasteland or not playerState.uisReady then
        return
    end
    local tables = exports.wasteland:GetCatalogueTables()
    if not tables then
        return
    end
    SendNUIMessage({ action = 'setWastelandCatalogue', data = tables.items })
    SendNUIMessage({ action = 'setWastelandBlueprints', data = tables.blueprints })
    cataloguePushed = true
end

AddEventHandler('wasteland:client:catalogueReady', pushCatalogue)

---@return boolean
local function pushSnapshot()
    local inventories = lib.callback.await('wasteland:inv:snapshot', false)
    if not inWasteland or not inventories then
        return false
    end
    local open = openContainerInv and inventories[tostring(openContainerInv)]
    if open and openContainerLayout then
        open.oven = openContainerLayout
    end
    SendNUIMessage({ action = 'setWastelandInventories', data = inventories })
    SendNUIMessage({ action = 'setWastelandHotbarVisible', data = true })
    snapshotPushed = true
    return true
end

---@return boolean
local function isWastelandInventoryReady()
    return cataloguePushed and snapshotPushed
end

exports('isWastelandInventoryReady', isWastelandInventoryReady)
local closeWastelandInventory
local closeWastelandWheel
local closeWastelandKeypad

---@param allowed boolean
exports('setWastelandPedFrontendAllowed', function(allowed)
    SetFrontendAllowed(allowed)
end)

---@return boolean
local function openWastelandInventory()
    if isInventoryOpen or not isWastelandInventoryReady() then
        return false
    end
    isInventoryOpen = true
    SendNUIMessage({ action = 'setWastelandInventoryVisible', data = true })
    SetNuiFocus(true, true)
    CreateThread(function()
        local ped = cache.ped
        while isInventoryOpen do
            if cache.ped ~= ped or not DoesEntityExist(ped) or IsEntityDead(ped) then
                closeWastelandInventory()
                break
            end
            Wait(200)
        end
    end)
    TriggerScreenblurFadeIn(0)
    return true
end

exports('openWastelandInventory', openWastelandInventory)

function closeWastelandInventory()
    if not isInventoryOpen then
        return
    end
    isInventoryOpen = false
    SendNUIMessage({ action = 'setWastelandInventoryVisible', data = false })
    SetNuiFocus(false, false)
    if openContainerInv then
        local invId = openContainerInv
        openContainerInv = nil
        openContainerLayout = nil
        SendNUIMessage({ action = 'setWastelandContainer', data = nil })
        TriggerServerEvent('wasteland:inv:closeContainer', invId)
    end
    TriggerScreenblurFadeOut(0)
end

exports('closeWastelandInventory', closeWastelandInventory)

---@param visible boolean
---@return boolean
exports('setWastelandInventorySheetVisible', function(visible)
    if not isInventoryOpen then
        return false
    end
    SendNUIMessage({ action = 'setWastelandInventoryVisible', data = visible == true })
    return true
end)

---@param mode 'cutout'|'full'|'off'
exports('setWastelandInventoryDim', function(mode)
    SendNUIMessage({ action = 'setWastelandInventoryDim', data = mode })
end)
---@type number?
local lastHeading = nil

---@class WastelandVitals
---@field health number
---@field water number
---@field food number
---@field temperature number
---@field wetness number
---@field oxygen number
---@field comfort number
---@field bleeding number
---@field poison number
---@field healthMax number?
---@field waterMax number?
---@field foodMax number?
---@param vitals WastelandVitals
local function setWastelandVitals(vitals)
    if not inWasteland or not vitals then
        return
    end
    SendNUIMessage({ action = 'setWastelandVitals', data = vitals })
end

RegisterNetEvent('wasteland:client:vitals', setWastelandVitals)

---@class WastelandStates
---@field privilege boolean?
---@field blocked boolean?
---@field decaying boolean?
---@field upkeep number|false|nil
---@field workbench integer?
---@type WastelandStates
local wastelandStates = {}

---@param states WastelandStates?
local function setWastelandStates(states)
    if not inWasteland then
        return
    end
    wastelandStates = type(states) == 'table' and states or {}
    SendNUIMessage({ action = 'setWastelandStates', data = wastelandStates })
end

RegisterNetEvent('wasteland:client:states', setWastelandStates)

---@class WastelandTargetInfo
---@field stability number
---@field health number
---@field max number
---@param info WastelandTargetInfo|false|nil
local function setWastelandTargetInfo(info)
    if not inWasteland then
        return
    end
    SendNUIMessage({ action = 'setWastelandTargetInfo', data = info or false })
end

exports('setWastelandTargetInfo', setWastelandTargetInfo)

---@class WastelandLookat
---@field icon string?
---@field verb string
---@field more boolean?
---@param lookat WastelandLookat|false|nil
local function setWastelandLookat(lookat)
    if not inWasteland then
        return
    end
    SendNUIMessage({ action = 'setWastelandLookat', data = lookat or false })
end

exports('setWastelandLookat', setWastelandLookat)

---@class WastelandNotify
---@field kind 'gain'|'loss'|'timer'
---@field label string
---@field amount integer?
---@field seconds integer?
---@field duration integer?
---@field key string?
---@param payload WastelandNotify
local function wastelandNotify(payload)
    if not inWasteland or not payload or not payload.label then
        return
    end
    SendNUIMessage({ action = 'wastelandNotify', data = payload })
end

exports('wastelandNotify', wastelandNotify)

RegisterNetEvent('wasteland:client:notify', wastelandNotify)

local function enterWastelandMode()
    if inWasteland then
        return
    end
    inWasteland = true
    SendNUIMessage({ action = 'setWastelandHudVisible', data = true })
    SendNUIMessage({ action = 'setWastelandMode', data = true })
    ui:setVitalsVisible(false)
    ui:setWatermarkMicVisible(false)
    ui:disableMenu()
    ui:setPauseMenuDisablePreview(true)
    ui:setPauseMenuDisableProfile(true)
    ui:disableWorldMap(true)
    DisplayRadar(false)
    CreateThread(function()
        while inWasteland do
            if isInventoryOpen then
                Wait(200)
            else
                local camRot = GetGameplayCamRot(0)
                local heading = 360.0 - ((camRot.z + 360.0) % 360.0)
                if heading >= 360.0 then heading = heading - 360.0 end
                heading = math.floor(heading * 10.0 + 0.5) / 10.0
                local delta = 360.0
                if lastHeading then
                    delta = math.abs(heading - lastHeading)
                    if delta > 180.0 then delta = 360.0 - delta end
                end
                if delta >= 0.2 then
                    lastHeading = heading
                    SendNUIMessage({ action = 'setWastelandHeading', data = heading })
                end
                Wait(0)
            end
        end
    end)
    CreateThread(function()
        while inWasteland and not cataloguePushed do
            pushCatalogue()
            Wait(500)
        end
        while inWasteland and not pushSnapshot() do
            Wait(1000)
        end
        while inWasteland do
            local queue = lib.callback.await('wasteland:craft:snapshot', false)
            if inWasteland and queue then
                SendNUIMessage({ action = 'setWastelandCraftQueue', data = queue })
                break
            end
            Wait(1000)
        end
    end)
end

AddStateBagChangeHandler('activity', ('player:%s'):format(cache.serverId), function(_, _, activity)
    if activity == WASTELAND_ACTIVITY then
        enterWastelandMode()
    else
        if not inWasteland then
            return
        end
        inWasteland = false
        snapshotPushed = false
        lastHeading = nil
        openContainerInv = nil
        openContainerLayout = nil
        closeWastelandInventory()
        if closeWastelandWheel then
            closeWastelandWheel()
        end
        if closeWastelandKeypad then
            closeWastelandKeypad()
        end
        SendNUIMessage({ action = 'setWastelandMode', data = false })
        ui:setVitalsVisible(true)
        ui:setWatermarkMicVisible(true)
        ui:enableMenu()
        ui:setPauseMenuDisablePreview(false)
        ui:setPauseMenuDisableProfile(false)
        ui:disableWorldMap(false)
        DisplayRadar(true)
        RefreshMinimapRadarVisibility()
        wastelandStates = {}
        SendNUIMessage({ action = 'setWastelandHudVisible', data = false })
        SendNUIMessage({ action = 'setWastelandStates', data = wastelandStates })
        SendNUIMessage({ action = 'setWastelandTargetInfo', data = false })
        SendNUIMessage({ action = 'setWastelandLookat', data = false })
        SendNUIMessage({ action = 'setWastelandHotbarVisible', data = false })
        SendNUIMessage({ action = 'setWastelandActiveBeltSlot', data = nil })
        SendNUIMessage({ action = 'setWastelandInventories', data = {} })
        SendNUIMessage({ action = 'setWastelandCraftQueue', data = { tasks = {} } })
        SendNUIMessage({ action = 'setWastelandWorkbenchLevel', data = 0 })
        SendNUIMessage({ action = 'setWastelandContainer', data = nil })
        SendNUIMessage({ action = 'setWastelandTechTree', data = nil })
    end
end)

---@param name string
exports('setWastelandProfile', function(name)
    SendNUIMessage({ action = 'setWastelandProfile', data = { name = name } })
end)

exports('isWastelandInventoryOpen', function()
    return isInventoryOpen
end)

---@return boolean
function IsWastelandMode()
    return inWasteland
end

---@param isVisible boolean
exports('setWastelandHotbarVisible', function(isVisible)
    SendNUIMessage({ action = 'setWastelandHotbarVisible', data = isVisible })
end)

---@param slot integer?
exports('setWastelandActiveBeltSlot', function(slot)
    SendNUIMessage({ action = 'setWastelandActiveBeltSlot', data = slot })
end)

---@param deltas WastelandInvDelta[]
RegisterNetEvent('wasteland:client:invDelta', function(deltas)
    if not snapshotPushed then
        return
    end
    SendNUIMessage({ action = 'wastelandInvDelta', data = deltas })
end)

---@param name string
---@param ... any
---@return table
local function awaitCallback(name, ...)
    local ok, result = pcall(lib.callback.await, name, false, ...)
    if ok and result then
        return result
    end
    return { ok = false, error = 'no_response' }
end

---@param action WastelandInvAction
RegisterNUICallback('wasteland:invAction', function(action, cb)
    cb(awaitCallback('wasteland:inv:action', action))
end)

---@param req { invId: integer, slot: integer, expectUid: integer, command: string, args?: table }
RegisterNUICallback('wasteland:invUse', function(req, cb)
    local result = awaitCallback('wasteland:item:use', req)
    if result.ok and result.fx then
        TriggerEvent('wasteland:client:useFx', result.fx)
    end
    cb(result)
end)

---@param queue WastelandCraftQueue
RegisterNetEvent('wasteland:craft:queueChanged', function(queue)
    if not inWasteland then
        return
    end
    SendNUIMessage({ action = 'setWastelandCraftQueue', data = queue })
end)

---@param level integer?
RegisterNetEvent('wasteland:client:workbenchLevel', function(level)
    SendNUIMessage({ action = 'setWastelandWorkbenchLevel', data = level or 0 })
end)

---@param data { shortname: WastelandShortname, amount: integer }
RegisterNUICallback('wasteland:craftQueue', function(data, cb)
    cb(awaitCallback('wasteland:craft:queue', data.shortname, data.amount))
end)

---@param data { invId: integer, characterId: integer }
RegisterNUICallback('wasteland:cupboardAuthorize', function(data, cb)
    cb(awaitCallback('wasteland:cupboard:authorize', data.invId, data.characterId))
end)

---@param data { invId: integer }
RegisterNUICallback('wasteland:cupboardDeauthorize', function(data, cb)
    cb(awaitCallback('wasteland:cupboard:deauthorize', data.invId))
end)

---@param data { invId: integer }
RegisterNUICallback('wasteland:cupboardClear', function(data, cb)
    cb(awaitCallback('wasteland:cupboard:clear', data.invId))
end)

---@param state WastelandCupboardState
RegisterNetEvent('wasteland:client:cupboardState', function(state)
    if not inWasteland or type(state) ~= 'table' then
        return
    end
    SendNUIMessage({ action = 'setWastelandCupboard', data = state })
end)

---@param data { taskId: integer }
RegisterNUICallback('wasteland:craftCancel', function(data, cb)
    cb(awaitCallback('wasteland:craft:cancel', data.taskId))
end)
RegisterNUICallback('wasteland:closeInventory', function(_, cb)
    closeWastelandInventory()
    cb(true)
end)

---@param data { slot: integer }
RegisterNUICallback('wasteland:selectBeltSlot', function(data, cb)
    closeWastelandInventory()
    if type(data) == 'table' and type(data.slot) == 'number' then
        TriggerEvent('wasteland:client:selectBeltSlot', data.slot)
    end
    cb(true)
end)

---@param data { open: boolean }
RegisterNUICallback('wasteland:backpackView', function(data, cb)
    exports.wasteland:setInventoryPreviewBackpack(data and data.open == true)
    cb(true)
end)

---@param payload WastelandContainerPayload?
local function setWastelandContainer(payload)
    if not inWasteland then
        return
    end
    openContainerInv = payload and payload.invId or nil
    openContainerLayout = payload and payload.layout or nil
    if payload then
        pushSnapshot()
    end
    SendNUIMessage({ action = 'setWastelandContainer', data = payload })
    if payload and payload.panel == 'oven' and not payload.oven then
        local invId = payload.invId
        CreateThread(function()
            local result = awaitCallback('wasteland:oven:state', invId)
            if not result.ok or openContainerInv ~= invId then
                return
            end
            SendNUIMessage({ action = 'setWastelandOvenState', data = result.state })
        end)
    end
end

RegisterNetEvent('wasteland:client:container', setWastelandContainer)

---@param state WastelandOvenState
RegisterNetEvent('wasteland:client:ovenState', function(state)
    if not inWasteland or not openContainerInv then
        return
    end
    SendNUIMessage({ action = 'setWastelandOvenState', data = state })
end)

---@param upkeep WastelandUpkeep
RegisterNetEvent('wasteland:client:upkeep', function(upkeep)
    if not inWasteland or not openContainerInv then
        return
    end
    SendNUIMessage({ action = 'setWastelandUpkeep', data = upkeep })
end)
---@param data { invId: integer, on: boolean }
RegisterNUICallback('wasteland:ovenToggle', function(data, cb)
    cb(awaitCallback('wasteland:oven:switch', data.invId, data.on == true))
end)
local wheelOpen = false

---@type string?
local wheelToken

local function dropWheelFocus()
    if not wheelOpen then
        return
    end
    wheelOpen = false
    SetNuiFocusKeepInput(false)
    TriggerScreenblurFadeOut(0)
    if not isInventoryOpen then
        SetNuiFocus(false, false)
    end
end

---@class WastelandWheelOption
---@field key string
---@field icon string
---@field title string
---@field description string
---@field requirements string?
---@field disabled boolean?
---@field active boolean?
---@param payload { kind: 'plan'|'upgrade'|'interact', block?: table, active?: string, options?: WastelandWheelOption[], token?: string }
---@return boolean opened
local function openWastelandWheel(payload)
    if not inWasteland or wheelOpen or isInventoryOpen or type(payload) ~= 'table' then
        return false
    end
    wheelOpen = true
    wheelToken = payload.token
    SendNUIMessage({ action = 'setWastelandWheel', data = payload })
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    TriggerScreenblurFadeIn(0)
    return true
end

exports('openWastelandWheel', openWastelandWheel)

function closeWastelandWheel()
    if not wheelOpen then
        return
    end
    SendNUIMessage({ action = 'setWastelandWheel', data = nil })
    dropWheelFocus()
end

exports('closeWastelandWheel', closeWastelandWheel)

---@param data { kind: string, key: string, token: string? }
RegisterNUICallback('wasteland:wheelSelect', function(data, cb)
    local token = wheelToken
    dropWheelFocus()
    if type(data) == 'table' and data.token == token then
        TriggerEvent('wasteland:client:wheelSelect', data)
    end
    cb(true)
end)
RegisterNUICallback('wasteland:closeWheel', function(_, cb)
    dropWheelFocus()
    TriggerEvent('wasteland:client:wheelClosed')
    cb(true)
end)

---@type { id: integer, mode: 'enter'|'change', guest: boolean }?
local keypadOpen = nil
function closeWastelandKeypad()
    if not keypadOpen then
        return
    end
    keypadOpen = nil
    SendNUIMessage({ action = 'setWastelandKeypad', data = nil })
    TriggerScreenblurFadeOut(0)
    if not isInventoryOpen then
        SetNuiFocus(false, false)
    end
end

---@param payload { id: integer, mode: 'enter'|'change', guest?: boolean }
---@return boolean opened
local function openWastelandKeypad(payload)
    if not inWasteland or keypadOpen or isInventoryOpen or wheelOpen
        or type(payload) ~= 'table' or type(payload.id) ~= 'number'
        or (payload.mode ~= 'enter' and payload.mode ~= 'change') then
        return false
    end
    keypadOpen = { id = payload.id, mode = payload.mode, guest = payload.guest == true }
    SendNUIMessage({
        action = 'setWastelandKeypad',
        data = { mode = payload.mode, guest = payload.guest == true },
    })
    SetNuiFocus(true, true)
    TriggerScreenblurFadeIn(0)
    CreateThread(function()
        while keypadOpen do
            if not inWasteland or IsEntityDead(cache.ped) then
                closeWastelandKeypad()
                break
            end
            Wait(200)
        end
    end)
    return true
end

exports('openWastelandKeypad', openWastelandKeypad)

---@param data { code: string }
RegisterNUICallback('wasteland:keypadSubmit', function(data, cb)
    local open = keypadOpen
    if not open or type(data) ~= 'table' or type(data.code) ~= 'string' then
        cb({ ok = false, error = 'no_keypad' })
        return
    end
    closeWastelandKeypad()
    local result
    if open.mode == 'enter' then
        result = awaitCallback('wasteland:lock:enter', open.id, data.code)
    else
        result = awaitCallback('wasteland:lock:code', open.id, data.code, open.guest)
    end
    if result.state then
        TriggerEvent('wasteland:client:lockState', result.state)
    end
    if result.warn then
        ui:notify({
            type = 'error',
            text = 'Further failed attempts will block code entry for some time',
        })
    end
    cb(result)
end)
RegisterNUICallback('wasteland:keypadClose', function(_, cb)
    closeWastelandKeypad()
    cb(true)
end)

---@param benchLevel integer?
local function setWastelandTechTree(benchLevel)
    if benchLevel and not inWasteland then
        return
    end
    SendNUIMessage({
        action = 'setWastelandTechTree',
        data = benchLevel and { benchLevel = benchLevel } or nil,
    })
end

RegisterNetEvent('wasteland:client:techTree', setWastelandTechTree)

---@param unlocked WastelandShortname[]
RegisterNetEvent('wasteland:client:unlocked', function(unlocked)
    SendNUIMessage({ action = 'setWastelandUnlocked', data = unlocked or {} })
end)

---@param data { techTreeLevel: integer, nodeId: integer, path: boolean }
RegisterNUICallback('wasteland:techUnlock', function(data, cb)
    cb(awaitCallback('wasteland:tech:unlock', data.techTreeLevel, data.nodeId, data.path == true))
end)
RegisterNUICallback('wasteland:closeTechTree', function(_, cb)
    TriggerServerEvent('wasteland:tech:close')
    cb(true)
end)

---@type 'map'|'respawn'|nil
local mapOpenMode = nil

---@class WastelandMapTransform
---@field centerX number
---@field centerY number
---@field size number
---@class WastelandMapOpenPayload
---@field mode 'map'|'respawn'
---@field transform WastelandMapTransform
---@field monuments? { label: string, x: number, y: number }[]
---@field death? { x: number, y: number }
local function closeWastelandMap()
    if not mapOpenMode then
        return
    end
    mapOpenMode = nil
    SendNUIMessage({ action = 'setWastelandMap', data = nil })
    if not isInventoryOpen then
        SetNuiFocus(false, false)
    end
    TriggerEvent('wasteland:client:mapClosed')
end

---@param payload WastelandMapOpenPayload
---@return boolean opened
local function openWastelandMap(payload)
    if not inWasteland or type(payload) ~= 'table' or type(payload.transform) ~= 'table'
        or (payload.mode ~= 'map' and payload.mode ~= 'respawn') then
        return false
    end
    if payload.mode == 'map' and (isInventoryOpen or wheelOpen or keypadOpen) then
        return false
    end
    if payload.mode == 'respawn' then
        closeWastelandInventory()
        closeWastelandWheel()
        closeWastelandKeypad()
    end
    local wasOpen = mapOpenMode ~= nil
    mapOpenMode = payload.mode
    SendNUIMessage({ action = 'setWastelandMap', data = payload })
    SetNuiFocus(true, true)
    if not wasOpen then
        CreateThread(function()
            while mapOpenMode do
                if not inWasteland then
                    closeWastelandMap()
                    break
                end
                Wait(200)
            end
        end)
    end
    return true
end

exports('openWastelandMap', openWastelandMap)

exports('closeWastelandMap', closeWastelandMap)

---@param payload { x: number, y: number, heading: number }
exports('setWastelandMapPlayer', function(payload)
    if not mapOpenMode then
        return
    end
    SendNUIMessage({ action = 'setWastelandMapPlayer', data = payload })
end)

---@param state { options?: table, reason?: string, life?: table }
exports('setWastelandRespawnState', function(state)
    if not inWasteland or type(state) ~= 'table' then
        return
    end
    SendNUIMessage({
        action = 'setWastelandRespawnOptions',
        data = { options = state.options or {}, reason = state.reason, life = state.life },
    })
end)

---@param data { id?: integer }
RegisterNUICallback('wasteland:respawnPick', function(data, cb)
    if mapOpenMode == 'respawn' then
        TriggerServerEvent('wasteland:respawn:pick', type(data) == 'table' and data.id or nil)
    end
    cb(true)
end)
RegisterNUICallback('wasteland:closeMap', function(_, cb)
    if mapOpenMode == 'map' then
        closeWastelandMap()
    end
    cb(true)
end)

---@return boolean
function IsWastelandSheetOpen()
    return (isInventoryOpen or keypadOpen ~= nil or mapOpenMode ~= nil or wheelOpen) == true
end

exports('isWastelandSheetOpen', IsWastelandSheetOpen)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end
    if not IsWastelandSheetOpen() then
        return
    end
    isInventoryOpen = false
    keypadOpen = nil
    wheelOpen = false
    mapOpenMode = nil
    SetNuiFocus(false, false)
    TriggerScreenblurFadeOut(0)
end)
local sleeping = false

---@param on boolean
---@param restoreHud boolean?
exports('setWastelandSleeping', function(on, restoreHud)
    on = on == true and inWasteland
    if sleeping == on then
        return
    end
    sleeping = on
    SendNUIMessage({ action = 'setWastelandSleeping', data = on })
    if on then
        SendNUIMessage({ action = 'setWastelandHudVisible', data = false })
        SendNUIMessage({ action = 'setWastelandHotbarVisible', data = false })
    elseif inWasteland and restoreHud ~= false then
        SendNUIMessage({ action = 'setWastelandHudVisible', data = true })
        SendNUIMessage({ action = 'setWastelandHotbarVisible', data = true })
    end
end)

CreateThread(function()
    while not playerState.uisReady do
        Wait(100)
    end
    if playerState.activity == WASTELAND_ACTIVITY then
        enterWastelandMode()
    end
end)
