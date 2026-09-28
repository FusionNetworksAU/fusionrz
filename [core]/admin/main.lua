---Client half of the admin resource.
---
---The menu itself lives in `ui` (ui/client/uis/admin.lua and reports.lua own
---the NUI and talk to admin:server:* directly). This file is the part that
---has to happen on a client: acting on the admin:client:* events the server
---emits, the spectator camera, and the self-options that are inherently
---local -- waypoints, nametags, saved positions.

-- shared/main.lua calls this too, but that file is a server_script -- the
-- client state never runs it, so locale() would be nil here without this.
lib.locale()

local core = exports.core
local ui = exports.ui

---@param kind 'success' | 'error' | 'inform'
---@param text string
local function notify(kind, text)
    ui:notify({ type = kind, text = text })
end

RegisterNetEvent('admin:notify', function(kind, text)
    notify(kind or 'inform', text)
end)

-- ---------------------------------------------------------------- menus ----

local function openAdminMenu()
    if not lib.callback.await('admin:server:canOpenMenu', false) then
        return notify('error', locale('no_perms'))
    end

    ui:setAdminMenuVisible(true)
end

lib.addKeybind({
    name = 'adminmenu',
    description = 'Open the admin menu',
    defaultKey = 'F6',
    onPressed = openAdminMenu,
})

RegisterCommand('adminmenu', openAdminMenu, false)

RegisterCommand('report', function()
    ui:setReportsMenuVisible(true)
end, false)

-- --------------------------------------------------------------- reports ----

---ui exposes the report surfaces as EXPORTS, not net events (see
---ui/client/uis/reports.lua), so the server's pushes have nothing to land on
---by themselves. This is that bridge: one net event per export, forwarded
---verbatim. Without it, filing a report or replying to one updates the
---database and then never reaches the screen.
---@type table<string, string>
local reportBridge = {
    ['admin:addMyReport'] = 'addMyReport',
    ['admin:addMyReportMessage'] = 'addMyReportMessage',
    ['admin:markMyReportAsResolved'] = 'markMyReportAsResolved',
    ['admin:addAdminReport'] = 'addAdminReport',
    ['admin:addAdminReportMessage'] = 'addAdminReportMessage',
    ['admin:markAdminReportAsResolved'] = 'markAdminReportAsResolved',
}

for eventName, exportName in pairs(reportBridge) do
    RegisterNetEvent(eventName, function(data)
        ui[exportName](ui, data)
    end)
end

-- --------------------------------------------------------- player state ----

RegisterNetEvent('admin:client:revive', function()
    core:reviveSelf(nil, true)
end)

RegisterNetEvent('admin:client:heal', function()
    local ped = cache.ped

    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetPedArmour(ped, 100)
    ClearPedBloodDamage(ped)
end)

---@param state boolean
RegisterNetEvent('admin:client:freeze', function(state)
    local ped = cache.ped

    FreezeEntityPosition(ped, state)
    SetPedCanRagdoll(ped, not state)

    notify('inform', state and locale('player_frozen') or locale('player_unfrozen'))
end)

-- ------------------------------------------------------------- spectate ----

local spectating = false

---The target's ped only exists locally once they are in scope, and being put
---in their routing bucket is what brings them into it -- which the server has
---just done. Waiting rather than failing immediately is the difference
---between spectate working and it working only for nearby players.
---@param serverId integer
---@return integer? ped
local function awaitTargetPed(serverId)
    local deadline = GetGameTimer() + 5000

    while GetGameTimer() < deadline do
        local playerIndex = GetPlayerFromServerId(serverId)

        if playerIndex ~= -1 then
            local ped = GetPlayerPed(playerIndex)

            if ped and ped ~= 0 and DoesEntityExist(ped) then
                return ped
            end
        end

        Wait(100)
    end

    return nil
end

local function stopSpectate()
    if not spectating then
        return
    end

    spectating = false

    NetworkSetInSpectatorMode(false, 0)

    local ped = cache.ped

    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    SetEveryoneIgnorePlayer(cache.playerId, false)
    FreezeEntityPosition(ped, false)
end

---@param serverId integer
RegisterNetEvent('admin:client:spectate', function(serverId)
    local ped = awaitTargetPed(serverId)

    if not ped then
        TriggerServerEvent('admin:server:spectateStop')

        return notify('error', locale('spectate_failed'))
    end

    if not spectating then
        spectating = true

        local ownPed = cache.ped

        SetEntityVisible(ownPed, false, false)
        SetEntityInvincible(ownPed, true)
        SetEveryoneIgnorePlayer(cache.playerId, true)
    end

    NetworkSetInSpectatorMode(false, 0)
    NetworkSetInSpectatorMode(true, ped)
end)

RegisterNetEvent('admin:client:stopSpectate', stopSpectate)

---Controls while spectating: arrows cycle, backspace exits. Registered as one
---thread that only runs while spectating, so it costs nothing otherwise.
CreateThread(function()
    while true do
        if spectating then
            -- INPUT_CELLPHONE_LEFT / RIGHT / CANCEL
            if IsControlJustPressed(0, 174) then
                TriggerServerEvent('admin:server:spectateCycle', -1)
            elseif IsControlJustPressed(0, 175) then
                TriggerServerEvent('admin:server:spectateCycle', 1)
            elseif IsControlJustPressed(0, 177) then
                TriggerServerEvent('admin:server:spectateStop')
            end

            Wait(0)
        else
            Wait(500)
        end
    end
end)

RegisterCommand('spectate', function(_, args)
    local userId = tonumber(args[1])

    if not userId then
        return TriggerServerEvent('admin:server:spectateStop')
    end

    TriggerServerEvent('admin:server:spectateStart', userId)
end, false)

-- ------------------------------------------------------------- nametags ----

local nametagsEnabled = false

local NAMETAG_DISTANCE = 100.0

---Reads the identity keys core publishes on each player's statebag, so this
---needs no lookup of its own and works for anyone in scope.
CreateThread(function()
    while true do
        if not nametagsEnabled then
            Wait(500)
        else
            local ownPed = cache.ped
            local ownCoords = GetEntityCoords(ownPed)

            for _, playerIndex in ipairs(GetActivePlayers()) do
                local ped = GetPlayerPed(playerIndex)

                if ped ~= ownPed and DoesEntityExist(ped) then
                    local coords = GetEntityCoords(ped)
                    local distance = #(ownCoords - coords)

                    if distance < NAMETAG_DISTANCE then
                        local serverId = GetPlayerServerId(playerIndex)
                        local state = Player(serverId).state
                        local label = ('%s [%s]'):format(state.username or GetPlayerName(playerIndex), state.userId or serverId)

                        SetDrawOrigin(coords.x, coords.y, coords.z + 1.05, 0)
                        SetTextScale(0.0, 0.32)
                        SetTextFont(4)
                        SetTextCentre(true)
                        SetTextColour(255, 255, 255, 215)
                        SetTextOutline()
                        BeginTextCommandDisplayText('STRING')
                        AddTextComponentSubstringPlayerName(label)
                        EndTextCommandDisplayText(0.0, 0.0)
                        ClearDrawOrigin()
                    end
                end
            end

            Wait(0)
        end
    end
end)

RegisterCommand('nametags', function()
    if not lib.callback.await('admin:server:canOpenMenu', false) then
        return notify('error', locale('no_perms'))
    end

    nametagsEnabled = not nametagsEnabled

    notify('inform', nametagsEnabled and locale('nametags_enabled') or locale('nametags_disabled'))
end, false)

-- --------------------------------------------------------- self options ----

RegisterCommand('tpwaypoint', function()
    local blip = GetFirstBlipInfoId(8)

    if not DoesBlipExist(blip) then
        return notify('error', locale('no_waypoint_set'))
    end

    local coords = GetBlipInfoIdCoord(blip)

    -- A waypoint carries no Z, so the ground has to be found before the
    -- server is asked to move anyone -- otherwise they land under the map.
    local groundZ = coords.z

    for height = 1000, 0, -25 do
        local found, z = GetGroundZFor_3dCoord(coords.x, coords.y, height + 0.0, false)

        if found then
            groundZ = z + 1.0
            break
        end

        Wait(0)
    end

    local success, message = lib.callback.await('admin:server:teleportToCoords', false, {
        x = coords.x,
        y = coords.y,
        z = groundZ,
    })

    notify(success and 'success' or 'error', message)
end, false)

RegisterCommand('savepos', function()
    local success, message = lib.callback.await('admin:server:saveCoords', false)

    notify(success and 'success' or 'error', message)
end, false)

RegisterCommand('returnpos', function()
    local success, message = lib.callback.await('admin:server:returnToSavedCoords', false)

    notify(success and 'success' or 'error', message)
end, false)

RegisterCommand('copycoords', function()
    local coords = GetEntityCoords(cache.ped)

    lib.setClipboard(('vec4(%.4f, %.4f, %.4f, %.4f)'):format(
        coords.x, coords.y, coords.z, GetEntityHeading(cache.ped)
    ))

    notify('success', locale('coords_copied'))
end, false)

RegisterCommand('tplobby', function()
    if lib.callback.await('admin:server:returnToLobby', false) then
        notify('success', locale('teleported_to_player'))
    else
        notify('error', locale('no_perms'))
    end
end, false)

---The configured destinations, shown as an ox_lib context menu rather than
---a command per location.
RegisterCommand('tpmenu', function()
    local locations = lib.callback.await('admin:server:getTeleportLocations', false)

    if not locations or #locations == 0 then
        return notify('error', locale('no_perms'))
    end

    local options = {}

    for index = 1, #locations do
        options[index] = {
            title = locations[index].label,
            onSelect = function()
                local success, message = lib.callback.await('admin:server:teleportToLocation', false, index)

                notify(success and 'success' or 'error', message)
            end,
        }
    end

    lib.registerContext({
        id = 'admin_teleports',
        title = 'Teleports',
        options = options,
    })

    lib.showContext('admin_teleports')
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then
        return
    end

    stopSpectate()

    FreezeEntityPosition(cache.ped, false)
end)
