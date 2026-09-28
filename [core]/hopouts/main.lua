local core = exports.core
local ui = exports.ui

local clientConfig = require 'config.client'
local sharedConfig = require 'config.shared'

---@type table?
local match

---Set once this life's death has been sent to the server, cleared on every
---respawn (hopouts:client:spawn). Declared up here so that handler can see
---it: a local declared further down is invisible to code above it, and
---without the reset only the first death of a match was ever reported.
local deathReported = false

---Weapons already warned about as missing, so the warning prints once.
---@type table<string, true>
local warnedWeapons = {}

---The 5-second pre-round countdown. Declared up here because the state
---handler that starts it comes earlier in the file than its body.
local runRoundCountdown

---@type table<integer, boolean>
local muted = {}

---@type { kind: 'double' | 'mapban', maps: table[]? }?
local activeVote

---@type table<string, integer>
local mapBanCounts = {}

local function inMatch()
    return match ~= nil
end

local HEADER_TEAMS = { 'red', 'yellow' }

---@param side string
---@return table
local function headerTeam(side)
    local members = match.roster and match.roster[side] or {}
    local players = {}

    for index = 1, #members do
        players[index] = {
            avatar = members[index].avatar,
            isAlive = members[index].alive == true,
        }
    end

    return {
        score = match.scores and match.scores[side] or 0,
        players = players,
    }
end

local function pushGameStats()
    if not match then
        return
    end

    local teams = {
        blue = headerTeam(match.side),
        red = { score = 0, players = {} },
    }

    local colourIndex = 1

    for _, side in ipairs(match.sides or {}) do
        if side ~= match.side and HEADER_TEAMS[colourIndex] then
            teams[HEADER_TEAMS[colourIndex]] = headerTeam(side)
            colourIndex += 1
        end
    end

    ui:setHopoutsGameStatsData({
        currentRound = match.round or 0,
        durationInSeconds = match.stateEndsAt and math.floor(math.max(0, match.stateEndsAt - GetGameTimer()) / 1000) or 0,
        teams = teams,
    })
end

---@param roster table
local function pushTeammates(roster)
    if not match or not roster then
        return
    end

    local own = roster[match.side] or {}

    ui:setHopoutsTeammatesData(own, {})
    ui:setHopoutsTeammatesVisible(true, false)
end

local function showHud(visible)
    ui:setHopoutsGameStatsVisible(visible)
    ui:setHopoutsHotbarVisible(visible)
    ui:setHopoutsTeammatesVisible(visible, false)
end

---States where the scoreboard / MVP / winner screen owns the screen. The
---hotbar, score header, teammate bars, health bar and minimap all stayed up
---underneath it and showed through the board.
local INTERMISSION_STATES = { roundend = true, matchend = true, switchsides = true }

local intermission = false

---@param on boolean
local function setIntermission(on)
    if intermission == on then
        return
    end

    intermission = on

    showHud(not on)
    ui:setVitalsVisible(not on)
    ui:setWatermarkMicVisible(not on)

    if not on then
        return
    end

    -- The minimap and GTA's own HUD are drawn by the game every frame.
    CreateThread(function()
        while intermission do
            HideHudAndRadarThisFrame()
            Wait(0)
        end
    end)
end

RegisterNetEvent('hopouts:client:joined', function(data)
    if GetResourceState('ui') == 'started' then
        if ui:isRankedMenuVisible() then
            ui:closeRankedMenu()
        end

        ui:closeMenu()
        ui:setMatchAcceptVisible(false)
        ui:setMapBanVisible(false)
    end

    match = {
        matchId = data.matchId,
        mapId = data.mapId,
        side = data.side,
        slot = data.slot,
        colours = data.colours,
        round = 0,
        scores = {},
        sides = {},
    }

    muted = {}

    showHud(true)
    pushGameStats()
end)

RegisterNetEvent('hopouts:client:left', function(reason)
    match = nil
    muted = {}

    -- Anyone who died in the last round left the match still dead: sent to
    -- spawn as a body on the ground. Bring them back first; the server's
    -- teleport to spawn (removePlayer) then moves the living ped.
    if IsEntityDead(cache.ped) or GetEntityHealth(cache.ped) <= 100 then
        pcall(function()
            exports.core:reviveSelf(nil, true)
        end)
    end

    NetworkSetInSpectatorMode(false, cache.ped)
    FreezeEntityPosition(cache.ped, false)
    ClearTimecycleModifier()

    -- Leaving from the end screen: the health bar and minimap come back for
    -- free roam; the hopouts-only HUD stays off below.
    setIntermission(false)
    showHud(false)
    ui:setHopoutScoreboardVisible(false, false)
    ui:setRequestDoubleVisible(false)

    if reason then
        ui:notify({ type = 'inform', text = ('You left the match: %s'):format(reason) })
    end
end)

RegisterNetEvent('hopouts:client:roster', function(data)
    if not match then
        return
    end

    match.sides = data.sides
    match.colours = data.colours
    match.scores = data.scores
    match.round = data.round
    match.roster = data.roster

    pushTeammates(data.roster)
    pushGameStats()
end)

RegisterNetEvent('hopouts:client:state', function(stateName, durationMsec)
    if not match then
        return
    end

    match.state = stateName
    match.stateEndsAt = durationMsec and (GetGameTimer() + durationMsec) or nil

    ui:setHopoutsGameStatsTimeFrozen(stateName ~= 'live')

    setIntermission(INTERMISSION_STATES[stateName] == true)

    if stateName == 'preround' then
        runRoundCountdown()
    end

    if stateName ~= 'roundend' and stateName ~= 'matchend' then
        ui:setHopoutScoreboardVisible(false, false)
        ui:setRoundMvpVisible(false)
    end

    pushGameStats()
end)

---Spawns land on the ground, every time. The old handler froze the ped the
---moment it arrived -- before the ground there had streamed in -- at a
---coordinate taken from a player's position (about a metre up), so players
---hung frozen in the air, and whether they did depended on load speed.
---Now: wait for the collision, find the ground, stand on it, then freeze.
RegisterNetEvent('hopouts:client:spawn', function(data)
    local coords = data.coords

    -- A new life: its death has not been reported yet.
    deathReported = false

    FreezeEntityPosition(cache.ped, false)

    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, coords.w or 0.0, true, false)

    local ped = cache.ped

    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    -- Resurrecting clears armour; every spawn is on full.
    SetPedArmour(ped, 100)
    ClearPedBloodDamage(ped)
    ClearPedTasksImmediately(ped)

    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(ped, coords.w or 0.0)

    local deadline = GetGameTimer() + 3000

    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(0)
    end

    -- Probe from above the spawn so a slightly-low coordinate still finds
    -- the floor; a ped's origin sits ~1m above its feet.
    local found, ground = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 2.0, false)

    -- A spawn set a few metres under the terrain (hilly maps) finds nothing
    -- from just above it; look again from well overhead.
    if not found then
        found, ground = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 50.0, false)
    end

    if found then
        SetEntityCoordsNoOffset(ped, coords.x, coords.y, ground + 1.0, false, false, false)
        SetEntityHeading(ped, coords.w or 0.0)
    end

    FreezeEntityPosition(ped, data.frozen == true)
end)

---The on-screen countdown before a round goes live: 5, 4, 3, 2, 1, then it
---clears as `live` arrives. Driven by the preround clock the server sent, so
---every player sees the same numbers.
runRoundCountdown = function()
    CreateThread(function()
        local last

        while match and match.state == 'preround' and match.stateEndsAt do
            local seconds = math.max(0, math.ceil((match.stateEndsAt - GetGameTimer()) / 1000))

            if seconds ~= last then
                last = seconds
                ui:setCountdownValue(seconds)
            end

            Wait(100)
        end

        ui:setCountdownValue(0)
    end)
end

RegisterNetEvent('hopouts:client:preround', function(data)
    FreezeEntityPosition(cache.ped, true)

    ui:notify({
        type = 'inform',
        text = data.pistolOnly and ('Round %s — pistols only'):format(data.round) or ('Round %s'):format(data.round),
    })
end)

RegisterNetEvent('hopouts:client:live', function()
    FreezeEntityPosition(cache.ped, false)
end)

---@param ped integer
---@param name string
---@param ammo integer
---@param equip boolean
local function giveWeapon(ped, name, ammo, equip)
    local hash = joaat(name)

    if not IsWeaponValid(hash) then
        if not warnedWeapons[name] then
            warnedWeapons[name] = true

            lib.print.warn(('[hopouts] weapon "%s" is not on this server; skipping it in the loadout.'):format(name))
        end

        return false
    end

    GiveWeaponToPed(ped, hash, ammo, false, equip)

    return true
end

-- ------------------------------------------------------------ the kit ----
--
-- The round's loadout as the hotbar sees it: which weapon sits in which slot,
-- and how many of each consumable are left. The keys (compat.lua raises
-- hopouts:itemBindPressed) used to go nowhere during a match -- only the
-- gamemodes resource listened, and only for its own rounds -- so 1-8 did
-- nothing and the hotbar never changed.

---@class HopoutsKit
---@field rifle string?
---@field pistol string?
---@field melee string?
---@field smoke string?
---@field armour integer
---@field medkits integer
---@field blunts integer
---@field busyUntil integer GetGameTimer until which an item is being used

---@type HopoutsKit?
local kit = nil

---@type string? last hotbar payload sent, to skip identical re-sends
local lastHotbar = nil

---@param item string
---@param default string
---@return string
local function keyFor(item, default)
    local ok, key = pcall(function()
        return exports.hopouts:GetItemKeybindKey(item)
    end)

    return ok and key and key ~= '' and key or default
end

---@param name string?
---@param selectedHash integer
---@param key string
---@return table
local function weaponSlot(name, selectedHash, key)
    if not name then
        return { selected = false, currentAmmo = 0, totalAmmo = 0, keybind = key }
    end

    local hash = joaat(name)
    local has = HasPedGotWeapon(cache.ped, hash, false)
    local _, clip = GetAmmoInClip(cache.ped, hash)

    return {
        selected = selectedHash == hash,
        currentAmmo = has and clip or 0,
        totalAmmo = has and GetAmmoInPedWeapon(cache.ped, hash) or 0,
        keybind = key,
    }
end

local function pushHotbar()
    if not kit then
        return
    end

    local selected = GetSelectedPedWeapon(cache.ped)

    -- rifle, smoke and repairkit are optional on the hotbar: a slot left out
    -- is not drawn at all. So a pistol-only round (no rifle, no smoke) shows
    -- no rifle slot, and hopouts has no repair kit to show.
    local data = {
        rifle = kit.rifle and weaponSlot(kit.rifle, selected, keyFor('rifle', '1')) or nil,
        pistol = weaponSlot(kit.pistol, selected, keyFor('pistol', '2')),
        axe = {
            selected = kit.melee ~= nil and selected == joaat(kit.melee),
            count = kit.melee and 1 or 0,
            keybind = keyFor('axe', '3'),
        },
        vest = { count = kit.armour, keybind = keyFor('vest', '4') },
        medkit = { count = kit.medkits, keybind = keyFor('medkit', '5') },
        blunt = { count = kit.blunts, keybind = keyFor('blunt', '6') },
        smoke = kit.smoke and {
            selected = selected == joaat(kit.smoke),
            count = GetAmmoInPedWeapon(cache.ped, joaat(kit.smoke)),
            keybind = keyFor('smoke', '8'),
        } or nil,
    }

    local encoded = json.encode(data)

    if encoded == lastHotbar then
        return
    end

    lastHotbar = encoded

    ui:setHopoutsHotbarData(data)
end

---Pressing the key of the weapon already in hand puts it away.
---@param name string?
local function toggleWeapon(name)
    if not name then
        return
    end

    local hash = joaat(name)

    if not HasPedGotWeapon(cache.ped, hash, false) then
        return
    end

    if GetSelectedPedWeapon(cache.ped) == hash then
        SetCurrentPedWeapon(cache.ped, `WEAPON_UNARMED`, true)
    else
        SetCurrentPedWeapon(cache.ped, hash, true)
    end
end

---@return boolean
local function canUseItem()
    return kit ~= nil
        and inMatch()
        and (match.state == 'live' or match.state == 'preround')
        and not IsEntityDead(cache.ped)
        and GetGameTimer() >= kit.busyUntil
end

local function useArmour()
    if not canUseItem() or kit.armour <= 0 or GetPedArmour(cache.ped) >= 100 then
        return
    end

    kit.busyUntil = GetGameTimer() + clientConfig.armorTimeMsec

    local done = ui:progressBar({
        duration = clientConfig.armorTimeMsec,
        label = 'Applying Armour',
        useWhileDead = false,
        canCancel = true,
        allowFalling = true,
        disable = { combat = true },
        anim = { dict = 'missmic4', clip = 'michael_tux_fidget', flag = 51 },
    })

    if kit then
        kit.busyUntil = 0

        if done and inMatch() then
            SetPedArmour(cache.ped, 100)
            kit.armour -= 1
        end
    end

    pushHotbar()
end

local function useBlunt()
    if not canUseItem() or kit.blunts <= 0 or GetPedArmour(cache.ped) >= 100 then
        return
    end

    kit.busyUntil = GetGameTimer() + clientConfig.bluntTimeMsec

    local done = ui:progressBar({
        duration = clientConfig.bluntTimeMsec,
        label = 'Smoking',
        useWhileDead = false,
        canCancel = true,
        allowFalling = true,
        disable = { combat = true },
        anim = { dict = 'amb@world_human_smoking@male@male_a@enter', clip = 'enter', flag = 51 },
        prop = {
            model = `p_cs_joint_01`,
            bone = 47419,
            pos = vec3(0.015, -0.009, 0.003),
            rot = vec3(55.0, 0.0, 110.0),
        },
    })

    if kit then
        kit.busyUntil = 0

        if done and inMatch() then
            SetPedArmour(cache.ped, math.min(GetPedArmour(cache.ped) + 25, 100))
            kit.blunts -= 1
        end
    end

    pushHotbar()
end

---A medkit heals over its duration rather than at once: you can keep
---fighting, but a burst of damage still outpaces it.
local function useMedkit()
    if not canUseItem() or kit.medkits <= 0 or GetEntityHealth(cache.ped) >= GetEntityMaxHealth(cache.ped) then
        return
    end

    kit.medkits -= 1
    kit.busyUntil = GetGameTimer() + 1500

    lib.requestAnimDict('mp_suicide')
    TaskPlayAnim(cache.ped, 'mp_suicide', 'pill', 2.0, 2.0, 1500, 51, 0, false, false, false)
    RemoveAnimDict('mp_suicide')

    pushHotbar()

    local steps = 25
    local perStep = math.floor(clientConfig.healthPerMedkit / steps + 0.5)
    local interval = math.floor(clientConfig.medKitTimeMsec / steps)

    CreateThread(function()
        for _ = 1, steps do
            Wait(interval)

            if not kit or not inMatch() or IsEntityDead(cache.ped) then
                return
            end

            local health = GetEntityHealth(cache.ped)
            local max = GetEntityMaxHealth(cache.ped)

            if health >= max then
                return
            end

            SetEntityHealth(cache.ped, math.min(max, health + perStep))
        end
    end)
end

---@param itemName string
AddEventHandler('hopouts:itemBindPressed', function(itemName)
    if not kit or not inMatch() or IsEntityDead(cache.ped) then
        return
    end

    if itemName == 'rifle' then
        toggleWeapon(kit.rifle)
    elseif itemName == 'pistol' then
        toggleWeapon(kit.pistol)
    elseif itemName == 'melee' then
        toggleWeapon(kit.melee)
    elseif itemName == 'smokes' then
        toggleWeapon(kit.smoke)
    elseif itemName == 'armor' then
        CreateThread(useArmour)
    elseif itemName == 'medkit' then
        useMedkit()
    elseif itemName == 'blunt' then
        CreateThread(useBlunt)
    end

    pushHotbar()
end)

local WEAPON_SLOT_CONTROLS = { 37, 157, 158, 159, 160, 161, 162, 163, 164, 165 }

CreateThread(function()
    while true do
        if kit and inMatch() then
            HudWeaponWheelIgnoreSelection()

            for index = 1, #WEAPON_SLOT_CONTROLS do
                DisableControlAction(0, WEAPON_SLOT_CONTROLS[index], true)
            end

            Wait(0)
        else
            Wait(500)
        end
    end
end)

CreateThread(function()
    while true do
        if kit and inMatch() then
            pushHotbar()
        end

        Wait(250)
    end
end)

---@param loadout table
RegisterNetEvent('hopouts:client:loadout', function(loadout)
    local ped = cache.ped

    RemoveAllPedWeapons(ped, true)

    kit = {
        rifle = nil,
        pistol = nil,
        melee = nil,
        smoke = nil,
        armour = loadout.armour or 0,
        medkits = loadout.medkits or 0,
        blunts = clientConfig.numJoints or 0,
        busyUntil = 0,
    }

    for index = 1, #loadout.weapons do
        local weapon = loadout.weapons[index]

        if giveWeapon(ped, weapon.name, weapon.ammo, index == 1) then
            if weapon.name == sharedConfig.rifleName then
                kit.rifle = weapon.name
            elseif weapon.name == sharedConfig.pistolName then
                kit.pistol = weapon.name
            elseif weapon.name == sharedConfig.meleeName then
                kit.melee = weapon.name
            end
        end
    end

    if (loadout.smokes or 0) > 0 and giveWeapon(ped, loadout.smokeName, loadout.smokes, false) then
        kit.smoke = loadout.smokeName
    end

    -- Every round starts on full armour; the vests in the kit top it back up.
    SetPedArmour(ped, 100)

    lastHotbar = nil
    pushHotbar()
end)

RegisterNetEvent('hopouts:client:clearLoadout', function()
    RemoveAllPedWeapons(cache.ped, true)

    kit = nil
    lastHotbar = nil
end)

local SPECTATE_DELAY_MSEC = 2000
local CONTROL_PREVIOUS = 174 -- left arrow
local CONTROL_NEXT = 175 -- right arrow

---@type integer? server id of the teammate being watched
local spectatingServerId = nil

---@return table[]
local function livingTeammates()
    local list = {}
    local members = match and match.roster and match.roster[match.side] or {}

    for index = 1, #members do
        local member = members[index]

        if member.alive and member.source ~= cache.serverId then
            local player = GetPlayerFromServerId(member.source)

            if player ~= -1 and DoesEntityExist(GetPlayerPed(player)) then
                list[#list + 1] = member
            end
        end
    end

    return list
end

local function stopSpectating()
    if not spectatingServerId then
        return
    end

    spectatingServerId = nil

    NetworkSetInSpectatorMode(false, cache.ped)
    ui:setSpectateVisible(false)
end

---@param member table
local function spectate(member)
    local ped = GetPlayerPed(GetPlayerFromServerId(member.source))

    spectatingServerId = member.source

    NetworkSetInSpectatorMode(true, ped)
    ui:setSpectateVisible(true)
end

---@param step integer 1 for the next teammate, -1 for the previous
local function cycleSpectate(step)
    local list = livingTeammates()

    if #list == 0 then
        return stopSpectating()
    end

    local current = 0

    for index = 1, #list do
        if list[index].source == spectatingServerId then
            current = index
            break
        end
    end

    local nextIndex = ((current - 1 + step) % #list) + 1

    spectate(list[nextIndex])
end

---@return boolean
local function shouldSpectate()
    return inMatch() and match.state == 'live' and IsEntityDead(cache.ped)
end

local function startSpectatingSoon()
    CreateThread(function()
        Wait(SPECTATE_DELAY_MSEC)

        if shouldSpectate() and not spectatingServerId then
            cycleSpectate(1)
        end
    end)
end

CreateThread(function()
    local nextUiAt = 0

    while true do
        if spectatingServerId then
            if not shouldSpectate() then
                stopSpectating()
            else
                DisableControlAction(0, CONTROL_PREVIOUS, true)
                DisableControlAction(0, CONTROL_NEXT, true)

                if IsDisabledControlJustPressed(0, CONTROL_PREVIOUS) then
                    cycleSpectate(-1)
                elseif IsDisabledControlJustPressed(0, CONTROL_NEXT) then
                    cycleSpectate(1)
                end

                -- The one being watched may have died or left since.
                local stillValid = false

                for _, member in ipairs(livingTeammates()) do
                    if member.source == spectatingServerId then
                        stillValid = true
                        break
                    end
                end

                if not stillValid then
                    cycleSpectate(1)
                end

                local now = GetGameTimer()

                if spectatingServerId and now >= nextUiAt then
                    nextUiAt = now + 250

                    local ped = GetPlayerPed(GetPlayerFromServerId(spectatingServerId))
                    local username = 'Teammate'

                    for _, member in ipairs(livingTeammates()) do
                        if member.source == spectatingServerId then
                            username = member.username or username
                            break
                        end
                    end

                    ui:setSpectateData({
                        id = spectatingServerId,
                        username = username,
                        health = math.max(0, GetEntityHealth(ped) - 100),
                        armor = GetPedArmour(ped),
                        ammo = GetAmmoInPedWeapon(ped, GetSelectedPedWeapon(ped)),
                        previousKeybind = 'LEFT ARROW',
                        nextKeybind = 'RIGHT ARROW',
                    })
                end
            end

            Wait(0)
        else
            Wait(250)
        end
    end
end)

---@param attacker integer? the ped or vehicle that did it, if known
local function reportOwnDeath(attacker)
    if deathReported or not inMatch() or match.state ~= 'live' then
        return
    end

    deathReported = true

    local killerServerId

    if attacker and attacker ~= 0 and attacker ~= cache.ped then
        if IsEntityAVehicle(attacker) then
            attacker = GetPedInVehicleSeat(attacker, -1)
        end

        if attacker and attacker ~= 0 and IsPedAPlayer(attacker) then
            local killerIndex = NetworkGetPlayerIndexFromPed(attacker)

            if killerIndex and killerIndex ~= -1 then
                killerServerId = GetPlayerServerId(killerIndex)
            end
        end
    end

    TriggerServerEvent('hopouts:server:reportDeath', killerServerId)

    -- Watch a living teammate for the rest of the round.
    startSpectatingSoon()
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or not inMatch() then
        return
    end

    local victim, attacker = args[1], args[2]

    if victim ~= cache.ped then
        return
    end

    if args[6] == 1 or IsEntityDead(victim) then
        reportOwnDeath(attacker)
    end
end)

CreateThread(function()
    while true do
        if inMatch() and match.state == 'live' then
            if not deathReported and IsEntityDead(cache.ped) then
                reportOwnDeath(GetPedSourceOfDeath(cache.ped))
            end

            Wait(100)
        else
            Wait(500)
        end
    end
end)

---@type { plan: table, startedAt: integer }?
local zone = nil

---@type integer?
local zoneBlip = nil

---@type { x: number, y: number, r: number }? what zoneBlip currently shows
local zoneBlipCircle = nil

---The thin ring on the map marking where the zone is heading.
---@type integer?
local nextZoneBlip = nil

---@type table? the circle nextZoneBlip was drawn for, so it is only rebuilt
---when the target actually changes (once per phase), not every frame
local nextZoneDrawn = nil

local zoneTimecycleOn = false
local gasMovingShown = false

RegisterNetEvent('hopouts:client:zone', function(plan)
    if type(plan) ~= 'table' or type(plan.start) ~= 'table' then
        return
    end

    zone = { plan = plan, startedAt = GetGameTimer() }
end)

---@param a number
---@param b number
---@param t number 0..1
---@return number
local function lerp(a, b, t)
    return a + (b - a) * t
end

---The circle `elapsed` ms into the round, whether it is on the move, and the
---circle it is heading for (nil once it has reached the last one).
---@param plan table
---@param elapsed integer
---@return { x: number, y: number, z: number, r: number } circle
---@return boolean moving
---@return { x: number, y: number, z: number, r: number }? nextCircle
local function zoneAt(plan, elapsed)
    local circle = plan.start
    local t = elapsed

    for index = 1, #plan.phases do
        local phase = plan.phases[index]

        if t < phase.holdMsec then
            return phase.from, false, phase.to, phase.holdMsec - t
        end

        t -= phase.holdMsec

        if t < phase.moveMsec then
            local k = t / phase.moveMsec

            return {
                x = lerp(phase.from.x, phase.to.x, k),
                y = lerp(phase.from.y, phase.to.y, k),
                z = lerp(phase.from.z, phase.to.z, k),
                r = lerp(phase.from.r, phase.to.r, k),
            }, true, phase.to, phase.moveMsec - t
        end

        t -= phase.moveMsec
        circle = phase.to
    end

    return circle, false, nil, nil
end

---The zone countdown under the round header: how long until it closes, then
---how long the close has left. Drawn natively so it cannot be lost to a UI
---reload mid-round.
---@param moving boolean
---@param msLeft integer?
local function drawZoneTimer(moving, msLeft)
    if not msLeft then
        return
    end

    local seconds = math.ceil(msLeft / 1000)
    local text = ('%s %d:%02d'):format(moving and 'ZONE CLOSING' or 'ZONE CLOSES IN', seconds // 60, seconds % 60)

    SetTextFont(4)
    SetTextScale(0.0, 0.42)
    SetTextCentre(true)
    SetTextOutline()

    if moving then
        SetTextColour(242, 178, 92, 255)
    else
        SetTextColour(241, 244, 247, 235)
    end

    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, 0.105)
end

---@return integer
local function zoneDamage()
    local remaining = match and match.stateEndsAt and math.max(0, match.stateEndsAt - GetGameTimer()) or 0
    local damage = 2
    local best

    for _, step in ipairs(clientConfig.damageIncreases or {}) do
        if step.timeLeft >= remaining and (not best or step.timeLeft < best) then
            best = step.timeLeft
            damage = step.health
        end
    end

    return damage
end

local function removeZoneBlip()
    if zoneBlip and DoesBlipExist(zoneBlip) then
        RemoveBlip(zoneBlip)
    end

    zoneBlip = nil
end

local function clearZoneBlip()
    removeZoneBlip()
    zoneBlipCircle = nil
end

local function removeNextZoneBlip()
    if nextZoneBlip and DoesBlipExist(nextZoneBlip) then
        RemoveBlip(nextZoneBlip)
    end

    nextZoneBlip = nil
    nextZoneDrawn = nil
end

---A white outline, not a filled disc: SetRadiusBlipEdge draws only the
---circle's edge, which reads as a thin line on the map and radar.
---@param circle table?
local function showNextZone(circle)
    if circle == nextZoneDrawn then
        return
    end

    removeNextZoneBlip()

    if not circle then
        return
    end

    nextZoneBlip = AddBlipForRadius(circle.x, circle.y, circle.z, circle.r)
    SetBlipColour(nextZoneBlip, 0)
    SetBlipAlpha(nextZoneBlip, 255)
    SetRadiusBlipEdge(nextZoneBlip, true)
    -- Above the red zone disc, which is replaced every 500ms.
    SetBlipPriority(nextZoneBlip, 12)

    nextZoneDrawn = circle

    -- Once per phase: the hold has just begun, which is the time to move.
    ui:notify({
        type = 'inform',
        text = 'Next zone marked on your map - rotate before it closes.',
        duration = 4000,
    })
end

---@param on boolean
local function setZoneTimecycle(on)
    if on == zoneTimecycleOn then
        return
    end

    zoneTimecycleOn = on

    if on then
        SetTimecycleModifier('REDMIST')
        SetTimecycleModifierStrength(clientConfig.zoneMaxTimecycleStrength or 0.65)
    else
        ClearTimecycleModifier()
    end
end

---@param visible boolean
local function setGasMoving(visible)
    if visible == gasMovingShown then
        return
    end

    gasMovingShown = visible
    ui:setGasMovingVisible(visible)
end

local function clearZone()
    zone = nil

    clearZoneBlip()
    removeNextZoneBlip()
    setZoneTimecycle(false)
    setGasMoving(false)
end

CreateThread(function()
    local nextDamageAt = 0
    local nextBlipAt = 0

    while true do
        if zone and inMatch() and match.state == 'live' then
            local elapsed = GetGameTimer() - zone.startedAt

            do
                local circle, moving, nextCircle, msLeft = zoneAt(zone.plan, elapsed)

                drawZoneTimer(moving, msLeft)
                local now = GetGameTimer()

                showNextZone(nextCircle)

                DrawMarker(1, circle.x, circle.y, circle.z - 60.0,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    circle.r * 2.0, circle.r * 2.0, 300.0,
                    255, 40, 40, 60,
                    false, false, 2, false, nil, nil, false)

                local drawn = zoneBlipCircle
                local changed = not drawn
                    or math.abs(drawn.r - circle.r) > 0.1
                    or math.abs(drawn.x - circle.x) > 0.1
                    or math.abs(drawn.y - circle.y) > 0.1

                if changed and now >= nextBlipAt then
                    nextBlipAt = now + 50
                    zoneBlipCircle = { x = circle.x, y = circle.y, r = circle.r }

                    local replacement = AddBlipForRadius(circle.x, circle.y, circle.z, circle.r)

                    SetBlipColour(replacement, 1)
                    SetBlipAlpha(replacement, 90)
                    SetBlipPriority(replacement, 1)

                    removeZoneBlip()
                    zoneBlip = replacement
                end

                setGasMoving(moving)

                local coords = GetEntityCoords(cache.ped)
                local outside = #(vec2(coords.x, coords.y) - vec2(circle.x, circle.y)) > circle.r
                local alive = not IsEntityDead(cache.ped)

                setZoneTimecycle(outside and alive)

                if outside and alive and now >= nextDamageAt then
                    nextDamageAt = now + 1000

                    SetEntityHealth(cache.ped, math.max(0, GetEntityHealth(cache.ped) - zoneDamage()))
                end

                Wait(0)
            end
        else
            if zone or zoneBlip or nextZoneBlip or zoneTimecycleOn or gasMovingShown then
                clearZone()
            end

            Wait(500)
        end
    end
end)

RegisterNetEvent('hopouts:client:kill', function(data)
    if not match then
        return
    end

    ui:notify({
        type = data.teamKill and 'error' or 'inform',
        text = data.killer
            and ('%s killed %s%s'):format(data.killer.username, data.victim.username, data.teamKill and ' (team kill)' or '')
            or ('%s died'):format(data.victim.username),
        duration = 2000,
    })
end)

---@return table<integer, string>
local function rosterAvatars()
    local avatars = {}

    for _, members in pairs(match and match.roster or {}) do
        for index = 1, #members do
            avatars[members[index].userId] = members[index].avatar
        end
    end

    return avatars
end

---@param data table
---@return table
local function buildScoreboardTeams(data)
    local ownSide = (match and match.side) or (data.sides and data.sides[1]) or 'A'
    local colourOf = { [ownSide] = 'blue' }
    local extra = { 'red', 'yellow' }
    local colourIndex = 1

    for _, side in ipairs(data.sides or {}) do
        if side ~= ownSide and extra[colourIndex] then
            colourOf[side] = extra[colourIndex]
            colourIndex += 1
        end
    end

    local teams = {
        blue = { players = {}, score = 0, displayName = 'Your Team' },
        red = { players = {}, score = 0, displayName = 'Enemy' },
    }

    for side, colour in pairs(colourOf) do
        teams[colour] = teams[colour] or { players = {}, displayName = 'Team ' .. tostring(side) }
        teams[colour].score = data.scores and data.scores[side] or 0
    end

    local avatars = rosterAvatars()

    for _, row in ipairs(data.rows or {}) do
        local team = teams[colourOf[row.side] or 'red']

        team.players[#team.players + 1] = {
            id = row.userId,
            username = row.username,
            avatar = avatars[row.userId],
            kills = row.kills or 0,
            deaths = row.deaths or 0,
            damage = row.damage or 0,
            headshotPercent = row.headshotPercent or 0,
            ping = row.ping or 0,
            rank = row.rank,
        }
    end

    return teams
end

---True while TAB is held for the live scoreboard.
local scoreboardHeld = false

RegisterNetEvent('hopouts:client:scoreboard', function(data)
    -- A live glance that arrives after TAB was let go is stale; drop it.
    if data.live and not scoreboardHeld then
        return
    end

    ui:setHopoutScoreboardData({
        currentRound = data.round or 0,
        roundsToWin = data.roundsToWin or 5,
        teams = buildScoreboardTeams(data),
    })

    if data.live then
        ui:setHopoutScoreboardVisible(true, false, false, true)
    else
        ui:setHopoutScoreboardVisible(true, data.isWinner == true)
    end
end)

-- Hold TAB during a match for the scoreboard with live numbers (kills, damage,
-- HS%, ping), refreshed every second while held. No cursor, no blur: it is a
-- glance mid-fight, not a menu. The round-end board is untouched by this.
lib.addKeybind({
    name = 'hopouts_scoreboard',
    description = 'Hopouts: hold for the live scoreboard',
    defaultKey = 'TAB',
    onPressed = function()
        if not inMatch() or (match.state ~= 'live' and match.state ~= 'preround') then
            return
        end

        scoreboardHeld = true

        CreateThread(function()
            while scoreboardHeld and inMatch() and (match.state == 'live' or match.state == 'preround') do
                TriggerServerEvent('hopouts:server:requestScoreboard')
                Wait(1000)
            end

            if scoreboardHeld then
                scoreboardHeld = false
                ui:setHopoutScoreboardVisible(false, false, false, true)
            end
        end)
    end,
    onReleased = function()
        if not scoreboardHeld then
            return
        end

        scoreboardHeld = false
        ui:setHopoutScoreboardVisible(false, false, false, true)
    end,
})

RegisterNetEvent('hopouts:client:roundMvp', function(mvp)
    if type(mvp) ~= 'table' then
        return
    end

    local avatar

    for _, members in pairs(match and match.roster or {}) do
        for index = 1, #members do
            if members[index].userId == mvp.userId then
                avatar = members[index].avatar
            end
        end
    end

    ui:setRoundMvpData({
        won = mvp.won == true,
        name = mvp.username or 'MVP',
        gang = 'FNRZ',
        kills = tonumber(mvp.kills) or 0,
        damage = tonumber(mvp.damage) or 0,
        profileImage = avatar,
        bannerImage = 'ccs/fnrz_default.webp',
    })
    ui:setRoundMvpVisible(true)

    SetTimeout(tonumber(mvp.displayMsec) or 4000, function()
        ui:setRoundMvpVisible(false)
    end)
end)

RegisterNetEvent('hopouts:client:roundEnd', function(data)
    if match then
        match.scores = data.scores
    end

    FreezeEntityPosition(cache.ped, true)
    pushGameStats()
end)

RegisterNetEvent('hopouts:client:switchSides', function(data)
    local cards = {}
    local members = match and match.roster and match.roster[match.side] or {}

    for index = 1, #members do
        cards[index] = {
            name = members[index].username,
            profileImage = members[index].avatar,
            bannerImage = 'ccs/fnrz_default.webp',
        }
    end

    ui:setSwitchSidesData(cards)

    ui:setSwitchSizesVisible(true)

    SetTimeout(data.durationMsec, function()
        ui:setSwitchSizesVisible(false)
    end)
end)

RegisterNetEvent('hopouts:client:sidesSwapped', function(swapped)
    if match then
        match.swapped = swapped
    end
end)

RegisterNetEvent('hopouts:client:matchEnd', function(data)
    local avatars = {}

    for _, members in pairs(match and match.roster or {}) do
        for index = 1, #members do
            avatars[members[index].userId] = members[index].avatar
        end
    end

    local winners = {}

    for index, row in ipairs(data.winners or {}) do
        winners[index] = {
            name = row.username,
            kills = row.kills,
            damage = row.damage,
            profileImage = avatars[row.userId],
        }
    end

    local won = match and data.winningSide ~= nil and data.winningSide == match.side
    local draw = data.winningSide == nil

    ui:setMatchWinnerData({
        title = draw and 'DRAW' or won and 'VICTORY' or 'DEFEAT',
        color = draw and '#B5B5B5' or won and '#2695FC' or '#E5484D',
        players = winners,
    })

    ui:setMatchWinnerPositions(data.offsets)
    ui:setMatchWinnerVisible(true)

    SetTimeout(data.previewDurationMsec, function()
        ui:setMatchWinnerVisible(false)
    end)
end)

RegisterNetEvent('hopouts:client:requestDouble', function(data)
    activeVote = { kind = 'double' }

    ui:setRequestDoubleTeams(data.teams)
    ui:setRequestDoubleVisible(true, true)

    local endsAt = GetGameTimer() + data.durationMsec

    CreateThread(function()
        while GetGameTimer() < endsAt do
            ui:setRequestDoubleCountdown(math.ceil((endsAt - GetGameTimer()) / 1000))

            Wait(250)
        end
    end)
end)

RegisterNetEvent('hopouts:client:requestDoubleCount', function(teamId, numAccepted)
    ui:setRequestDoubleTeamCount(teamId, numAccepted)
end)

RegisterNetEvent('hopouts:client:requestDoubleFailed', function()
    activeVote = nil

    ui:setVotesVisible(false)
    ui:setRequestDoubleVisible(false)
    ui:notify({ type = 'inform', text = 'The rematch was called off.' })
end)

local function pushVotes(maps)
    local rows = {}

    for index = 1, #maps do
        local map = maps[index]

        rows[index] = {
            id = map.id,
            label = map.label,
            image = map.image,
            votes = mapBanCounts[map.id] or 0,
        }
    end

    ui:setVotesData({ title = 'Ban a map', options = rows })
end

RegisterNetEvent('hopouts:client:doubleMapVote', function(data)
    activeVote = { kind = 'mapban', maps = data.maps }
    mapBanCounts = {}

    ui:setRequestDoubleVisible(false)
    pushVotes(data.maps)
    ui:setVotesVisible(true)

    local endsAt = GetGameTimer() + data.durationMsec

    CreateThread(function()
        while activeVote and activeVote.kind == 'mapban' and GetGameTimer() < endsAt do
            ui:setVotesCountdown(math.ceil((endsAt - GetGameTimer()) / 1000))

            Wait(250)
        end

        if activeVote and activeVote.kind == 'mapban' then
            ui:setVotesVisible(false)
            activeVote = nil
        end
    end)
end)

RegisterNetEvent('hopouts:client:doubleMapBanned', function(mapId, count)
    mapBanCounts[mapId] = count

    if activeVote and activeVote.kind == 'mapban' then
        pushVotes(activeVote.maps)
    end
end)

---@param vote any map id for a ban, false/'skip' to pass, boolean for a rematch
exports('handleVotePressed', function(vote)
    if not activeVote then
        return false
    end

    if activeVote.kind == 'mapban' then
        if vote == false or vote == 'skip' or vote == nil then
            return lib.callback.await('hopouts:server:voteForDoubleMapSkip', false)
        end

        return lib.callback.await('hopouts:server:voteForDoubleMapBan', false, tostring(vote))
    end

    if activeVote.kind == 'double' then
        return lib.callback.await('hopouts:server:submitDoubleVote', false, vote == true)
    end

    return false
end)

---@param vote boolean
---@return boolean success
exports('submitRequestDoubleVote', function(vote)
    if not inMatch() then
        return false
    end

    return lib.callback.await('hopouts:server:submitDoubleVote', false, vote == true)
end)

---@param targetUserId integer
---@return boolean isMuted
exports('togglePlayerMute', function(targetUserId)
    if not inMatch() then
        return false
    end

    local isMuted = lib.callback.await('hopouts:server:togglePlayerMute', false, targetUserId)

    muted[targetUserId] = isMuted or nil

    if GetResourceState('pma-voice') == 'started' then
        pcall(function()
            exports['pma-voice']:setPlayerMuted(targetUserId, isMuted)
        end)
    end

    return isMuted == true
end)

AddEventHandler('ui:voteToKickRequested', function(targetUserId)
    if not inMatch() then
        return
    end

    TriggerServerEvent('hopouts:server:voteToKick', targetUserId)
end)

RegisterNetEvent('hopouts:client:kickVote', function(data)
    ui:notify({
        type = 'inform',
        text = ('Vote to kick: %s/%s'):format(data.votes, data.required),
        duration = 2500,
    })
end)

local pingTexture

local function ensurePingTexture()
    if pingTexture then
        return pingTexture
    end

    local dict = clientConfig.pingTextureDict
    local runtime = CreateRuntimeTxd(dict)
    local dui = CreateDui(('nui://%s/web/index.html'):format(cache.resource), 64, 64)

    CreateRuntimeTextureFromDuiHandle(runtime, 'ping', GetDuiHandle(dui))

    pingTexture = { dict = dict, dui = dui }

    return pingTexture
end

---@param hex string
local function setPingColour(hex)
    local texture = ensurePingTexture()

    SendDuiMessage(texture.dui, json.encode({ type = 'setIconColor', color = hex }))
end

RegisterNetEvent('hopouts:client:sidesSwapped', function()
    if not match or not match.colours or not match.side then
        return
    end

    local colour = match.colours[match.side]

    if colour then
        setPingColour(colour.hex)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then
        return
    end

    if pingTexture then
        DestroyDui(pingTexture.dui)
    end

    FreezeEntityPosition(cache.ped, false)
    showHud(false)
end)

CreateThread(function()
    while true do
        if inMatch() and match.state == 'live' then
            pushGameStats()

            Wait(250)
        else
            Wait(1000)
        end
    end
end)

---For other resources that must not act mid-match (the character editor).
---@return boolean
exports('isInMatch', function()
    return inMatch() == true
end)

-- ----------------------------------------------------------- forfeit vote ----
-- server/forfeit.lua runs the vote; this shows it. /ff and /ff no are server
-- commands, so there is nothing to register here.

---@type table?
local ffVote

RegisterNetEvent('hopouts:client:ffNotify', function(data)
    if type(data) == 'table' and data.text then
        ui:notify({ type = data.type or 'inform', text = data.text, duration = 6000 })
    end
end)

RegisterNetEvent('hopouts:client:ffVote', function(data)
    if type(data) ~= 'table' or not data.active then
        ffVote = nil
        lib.hideTextUI()

        return
    end

    local first = ffVote == nil

    ffVote = data
    ffVote.endsAt = GetGameTimer() + (tonumber(data.endsIn) or 0)

    if not first then
        return
    end

    CreateThread(function()
        while ffVote do
            local secondsLeft = math.max(0, math.ceil((ffVote.endsAt - GetGameTimer()) / 1000))

            lib.showTextUI(('FORFEIT VOTE  ·  %d/%d YES  ·  %d NO  ·  %ds  —  /ff yes  ·  /ff no'):format(
                ffVote.yes or 0, ffVote.required or 3, ffVote.no or 0, secondsLeft
            ), { position = 'top-center' })

            Wait(500)
        end

        lib.hideTextUI()
    end)
end)

-- Leaving the match mid-vote.
RegisterNetEvent('hopouts:client:left', function()
    if ffVote then
        ffVote = nil
        lib.hideTextUI()
    end
end)
