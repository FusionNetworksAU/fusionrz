local locations = require '@core.data.locations'

local core = exports.core

local playerState = LocalPlayer.state

local isVisible = false

function IsMenuVisible()
    return isVisible
end

local function openMenu()
    if isVisible then
        return
    end

    TriggerScreenblurFadeIn(0)

    SendNUIMessage({ action = 'setMenuVisible', data = true })
    SetNuiFocus(true, true)

    isVisible = true

    core:Subscribe('teleportCounts')
    core:Subscribe('gamemodePortalCounts')

    RefreshMinimapRadarVisibility()
end

local function closeMenu()
    if not isVisible then
        return
    end

    TriggerScreenblurFadeOut(0)

    exports.shop:stopPreview(false)

    SendNUIMessage({ action = 'setMenuVisible', data = false })

    if not IsRankedOverlayFocused() then
        SetNuiFocus(false, false)
    end

    isVisible = false

    core:Unsubscribe('teleportCounts')
    core:Unsubscribe('gamemodePortalCounts')

    RefreshMinimapRadarVisibility()
end

local keybind = lib.addKeybind({
    name = 'menu',
    description = 'Open Menu',
    defaultKey = 'K',
    onPressed = function()
        openMenu()
    end
})

local function disableMenu()
    closeMenu()

    if keybind.disabled then
        return
    end

    keybind:disable(true)
end

exports('disableMenu', disableMenu)

exports('closeMenu', closeMenu)

exports('openMenu', openMenu)

local function enableMenu()
    if not keybind.disabled then
        return
    end

    keybind:disable(false)
end

exports('enableMenu', enableMenu)

RegisterNUICallback('hideMenu', function(_, cb)
    cb(1)

    closeMenu()
end)

---@param mapId string
RegisterNUICallback('useGlobalTeleport', function(mapId, cb)
    cb(1)

    local location = locations[mapId]

    if not location then
        lib.print.error(('Unable to find location: %s'):format(mapId))
        return
    end

    disableMenu()
    core:TeleportToCoords(location.coords, true)
    enableMenu()
end)

---@param mapId string
RegisterNUICallback('spectateGlobalTeleport', function(mapId, cb)
    cb(1)

    local location = locations[mapId]

    if not location then
        lib.print.error(('Unable to find location: %s'):format(mapId))
        return
    end

    disableMenu()
    DoScreenFadeOut(0)
    Wait(500)

    local coords = location.coords

    local camHeight = 80.0 -- how high above the target
    local camDistance = 40.0 -- how far back (for angled view)

    local heading = coords.w or 0.0
    local offsetX = camDistance * math.sin(math.rad(heading))
    local offsetY = camDistance * math.cos(math.rad(heading))

    local camCoords = vec3(
        coords.x - offsetX,
        coords.y - offsetY,
        coords.z + camHeight
    )

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, camCoords.x, camCoords.y, camCoords.z)
    PointCamAtCoord(cam, coords.x, coords.y, coords.z)
    RenderScriptCams(true, false, 0, true, false)

    SetFocusPosAndVel(coords.x, coords.y, coords.z, 0.0, 0.0, 0.0)

    exports.ui:setVitalsVisible(false)
    exports.ui:setWatermarkMicVisible(false)
    exports.ui:setTextUI({ title = 'SPECTATING', subtitle = 'CLICK BACKSPACE TO STOP' })

    DoScreenFadeIn(500)

    -- keybind to stop spectating, make player invisible? and invincible?
    CreateThread(function()
        while not playerState.isDead do
            Wait(0)

            DisableAllControlActions(0)

            if IsDisabledControlJustPressed(0, 194) then
                break
            end
        end

        DoScreenFadeOut(500)
        Wait(500)

        DestroyCam(cam, false)
        ClearFocus()
        RenderScriptCams(false, false, 0, true, false)

        exports.ui:setVitalsVisible(true)
        exports.ui:setWatermarkMicVisible(true)
        exports.ui:hideTextUI()

        DoScreenFadeIn(500)
        enableMenu()
    end)
end)

---@param data { mapId: string; isFavorite: boolean }
RegisterNUICallback('favoriteGlobalTeleport', function(data, cb)
    local location = locations[data.mapId]

    if not location then
        lib.print.error(('Unable to find location: %s'):format(data.mapId))
        return cb(false)
    end

    local key = ('fusionrz:teleport_favorited:%s'):format(data.mapId)

    if data.isFavorite then
        SetResourceKvpInt(key, 1)
    else
        DeleteResourceKvp(key)
    end

    cb(true)
end)

---@param gamemode string
RegisterNUICallback('selectGamemode', function(gamemode, cb)
    cb(1)

    closeMenu()

    if gamemode == 'shooting_scenes_1' then
        if GetResourceState('sns') ~= 'started' then
            exports.ui:notify({ type = 'error', text = 'Shooting & Scenes is not available on this server.' })
            return
        end

        exports.sns:enter()
        return
    end

    if gamemode == 'hopouts_1' then
        if GetResourceState('ranked') ~= 'started' then
            exports.ui:notify({ type = 'error', text = 'Ranked is not available on this server.' })
            return
        end

        exports.ui:openRankedMenu()
        return
    end

    if GetResourceState('gamemodes') ~= 'started' then
        exports.ui:notify({ type = 'error', text = 'Gamemodes are not available on this server.' })
        return
    end

    exports.gamemodes:enterMode(gamemode)
end)

---@param name string
RegisterNUICallback('spawnGlobalWeapon', function(name, cb)
    cb(1)

    TriggerServerEvent('uis:server:spawnGlobalWeapon', name)
end)

---@param name string
RegisterNUICallback('removeGlobalWeapon', function(name, cb)
    cb(1)

    TriggerServerEvent('uis:server:removeGlobalWeapon', name)
end)

RegisterNUICallback('removeAllGlobalWeapons', function(_, cb)
    cb(1)

    TriggerServerEvent('uis:server:removeAllGlobalWeapons')
end)

---@param weaponHash string
RegisterNetEvent('core:onGiveWeapon', function(weaponHash)
    SendNUIMessage({ action = 'onGiveWeapon', data = weaponHash })
end)

---@param weaponHash string
RegisterNetEvent('core:onRemoveWeapon', function(weaponHash)
    SendNUIMessage({ action = 'onRemoveWeapon', data = weaponHash })
end)

RegisterNetEvent('core:onRemoveAllWeapons', function()
    SendNUIMessage({ action = 'onRemoveAllWeapons', data = {} })
end)

---@param weapons string[]
RegisterNetEvent('core:setWeaponWhitelist', function(weapons)
    SendNUIMessage({ action = 'setWeaponsWhitelist', data = weapons })

    ---@type table[]
    local list = {}

    if type(weapons) == 'table' then
        for i = 1, #weapons do
            local name = weapons[i]

            if type(name) == 'string' then
                name = name:upper()
                local weapon = core:GetWeaponDataById(name)

                if weapon then
                    list[#list + 1] = {
                        name = name,
                        label = weapon.label,
                        type = weapon.type,
                        hasAce = not not weapon.ace,
                    }
                else
                    list[#list + 1] = {
                        name = name,
                        label = name:gsub('^WEAPON_', ''):gsub('_', ' '),
                        type = 'pistol',
                        hasAce = false,
                    }
                end
            end
        end
    end

    SendNUIMessage({ action = 'setGlobalWeapons', data = list })
end)

RegisterNetEvent('core:resetWeaponWhitelist', function()
    SendNUIMessage({ action = 'resetWeaponsWhitelist', data = {} })
    TriggerEvent('ui:forceRefreshGlobalWeapons')
end)

---@param counts table<string, integer>
RegisterNetEvent('core:client:teleportCounts', function(counts)
    SendNUIMessage({ action = 'mergeTeleportPlayerCounts', data = counts })
end)

---@param counts GamemodePortalCounts
RegisterNetEvent('gamemodes:client:portalCounts', function(counts)
    SendNUIMessage({ action = 'mergeGamemodePlayerCounts', data = counts })
end)