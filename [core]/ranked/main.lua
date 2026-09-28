local ui = exports.ui
local core = exports.core

local config = require 'config.client'

---@param exportName string
RegisterNetEvent('ranked:client:uiExport', function(exportName, ...)
    if type(exportName) ~= 'string' then
        return
    end

    local fn = ui[exportName]

    if type(fn) ~= 'function' then
        return lib.print.warn(('[ranked] ui has no export "%s"'):format(exportName))
    end

    fn(ui, ...)
end)

---@type integer?
local podiumCam = nil

---@type integer[] podium ped handles, slot order
local podiumPeds = {}

---@type boolean
local podiumActive = false

local function clearPodiumPeds()
    for index = 1, #podiumPeds do
        if DoesEntityExist(podiumPeds[index]) then
            DeleteEntity(podiumPeds[index])
        end
    end

    podiumPeds = {}
end

---@param slot integer
---@return vector3
local function podiumSlotCoords(slot)
    local podium = config.podium
    local offsets = podium.offsets.solo
    local offset = offsets[slot] or offsets[1]

    local heading = math.rad(podium.position.w)
    local forward = vector3(-math.sin(heading), math.cos(heading), 0.0)
    local right = vector3(math.cos(heading), math.sin(heading), 0.0)

    return vector3(podium.position.x, podium.position.y, podium.position.z)
        + forward * offset.forward
        + right * offset.right
end

---Where the podium camera sits: `distance` behind the podium point along its
---heading, `cameraHeight` above it, `cameraRight` to the side.
---@return vector3
local function podiumCameraCoords()
    local podium = config.podium
    local heading = math.rad(podium.position.w)
    local sideways = podium.cameraRight or 0.0

    return vector3(
        podium.position.x + math.sin(heading) * podium.distance + math.cos(heading) * sideways,
        podium.position.y - math.cos(heading) * podium.distance + math.sin(heading) * sideways,
        podium.position.z + (podium.cameraHeight or 1.0)
    )
end

---The floor under a slot. CreatePed takes the z of the ped's feet, and the
---configured position is a player origin (~1m up), which is why the peds
---stood a metre in the air. Probed from just above; falls back to the usual
---origin-to-feet drop when the collision there has not streamed in yet.
---@param coords vector3
---@return number
local function floorZ(coords)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)

    local found, ground = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 0.5, false)

    if found and ground > coords.z - 3.0 then
        return ground
    end

    return coords.z - 1.0
end

---Projects a world point through the podium camera to 0..1 screen
---coordinates. Worked out from the camera's configuration rather than asked
---of the game, because the game only answers for the camera that is rendering
---right now, and the podium camera is still easing in when the party lands.
---@param point vector3
---@return number x, number y
local function projectThroughPodiumCamera(point)
    local podium = config.podium
    local heading = math.rad(podium.position.w)
    local pitch = math.rad(podium.cameraPitch or -5.0)

    local forward = vector3(-math.sin(heading) * math.cos(pitch), math.cos(heading) * math.cos(pitch), math.sin(pitch))
    local right = vector3(math.cos(heading), math.sin(heading), 0.0)
    local up = vector3(
        right.y * forward.z - right.z * forward.y,
        right.z * forward.x - right.x * forward.z,
        right.x * forward.y - right.y * forward.x
    )

    local offset = point - podiumCameraCoords()
    local depth = math.max(offset.x * forward.x + offset.y * forward.y + offset.z * forward.z, 0.01)
    local across = offset.x * right.x + offset.y * right.y + offset.z * right.z
    local height = offset.x * up.x + offset.y * up.y + offset.z * up.z

    local width, screenHeight = GetActiveScreenResolution()
    local tanHalfV = math.tan(math.rad(podium.fov) / 2)
    local tanHalfH = tanHalfV * (width / screenHeight)

    return 0.5 + (across / depth) / (2 * tanHalfH), 0.5 - (height / depth) / (2 * tanHalfV)
end

---Where a card's centre sits relative to its ped's feet on screen, per config
---`cardRow`: row 1 across the shins, row 2 just under the feet. The NUI
---centres each card on the point it is given (translate -50%/-50%); this used
---to subtract half a card width as if it were a top-left corner, which put
---every card 190px left of its ped and pushed the outer one off screen.
local CARD_ROW_OFFSET = { [1] = -0.03, [2] = 0.045 }

local DEFAULT_MODEL = `mp_m_freemode_01`

---Dresses a podium ped as its player. The saved appearance comes with the
---party push (server/parties.lua), including the model, so a player on a
---female ped stands as one. Without an appearance the ped keeps the default
---look rather than failing.
---@param member table
---@param feet vector3
---@param heading number
---@return integer ped, 0 if it could not be made
local function createMemberPed(member, feet, heading)
    local look = type(member.appearance) == 'table' and member.appearance or nil
    local model = DEFAULT_MODEL

    if look and look.model then
        local hash = type(look.model) == 'number' and look.model or joaat(look.model)

        if IsModelInCdimage(hash) and IsModelValid(hash) then
            model = hash
        end
    end

    lib.requestModel(model, 10000)

    local ped = CreatePed(4, model, feet.x, feet.y, feet.z, heading, false, false)

    SetModelAsNoLongerNeeded(model)

    if ped == 0 then
        return 0
    end

    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetPedDefaultComponentVariation(ped)

    if look and GetResourceState('appearance') == 'started' then
        pcall(function()
            exports.appearance:setPedAppearance(ped, look)
        end)
    end

    -- Held, not holstered: an armed ped at rest stands in the rifle-low
    -- idle, which is the pose the original lobby shows.
    local weapon = config.podium.weapon

    if weapon then
        local hash = joaat(weapon)

        if IsWeaponValid(hash) then
            GiveWeaponToPed(ped, hash, 1, false, true)
            SetCurrentPedWeapon(ped, hash, true)
        end
    end

    return ped
end

---@param members table[]
---@param slots integer? the mode's team size; defaults to every configured slot
local function buildPodium(members, slots)
    clearPodiumPeds()

    ---@type table[]
    local positions = {}

    -- startPodium puts the camera behind the podium point looking along
    -- position.w, so a ped given that same heading shows the camera its back.
    -- Turned round, it faces the lens.
    local heading = (config.podium.position.w + 180.0) % 360.0
    local offsets = config.podium.offsets.solo

    -- Every slot gets a position, filled or not: the NUI pairs them with the
    -- party by index and draws the empty ones as the "+" invite cards.
    -- Only as many slots as the mode holds (never fewer than the party has).
    local count = math.min(#offsets, math.max(tonumber(slots) or #offsets, #members, 1))

    for index = 1, count do
        local coords = podiumSlotCoords(index)
        local feet = vector3(coords.x, coords.y, floorZ(coords))
        local member = members[index]

        if member then
            local ped = createMemberPed(member, feet, heading)

            if ped ~= 0 then
                podiumPeds[#podiumPeds + 1] = ped
            end
        end

        -- The NUI places each card at a screen fraction ({x, y}, top-left).
        local screenX, screenY = projectThroughPodiumCamera(feet)
        local row = offsets[index].cardRow or 2

        positions[index] = {
            userId = member and member.userId or nil,
            x = screenX,
            y = screenY + (CARD_ROW_OFFSET[row] or CARD_ROW_OFFSET[2]),
        }
    end

    ui:setPartyPositions(positions)
end

local BACKDROP_TXD = 'ranked_lobby'
local BACKDROP_TEXTURE = 'backdrop'

---@type boolean? nil = not tried yet, false = the image failed to load
local backdropLoaded = nil

---Loads config.podium.backdrop.image into a runtime texture, once.
---@return boolean
local function loadBackdrop()
    if backdropLoaded ~= nil then
        return backdropLoaded
    end

    local backdrop = config.podium.backdrop
    backdropLoaded = false

    if not backdrop or not backdrop.image then
        return false
    end

    local txd = CreateRuntimeTxd(BACKDROP_TXD)

    if not CreateRuntimeTextureFromImage(txd, BACKDROP_TEXTURE, backdrop.image) then
        lib.print.warn(('[ranked] lobby backdrop "%s" could not be loaded; is it listed in fxmanifest files?'):format(backdrop.image))
        return false
    end

    backdropLoaded = true

    return true
end

---Hangs the backdrop image behind the party as two textured triangles in the
---world, so the peds stand in front of it and it fills the camera's view.
---Drawn every frame while the lobby is open; it is not an entity.
local function drawBackdropThread()
    local podium = config.podium
    local backdrop = podium.backdrop

    if not backdrop then
        return
    end

    -- Without the image, hang a plain navy panel instead: a missing file then
    -- still reads as "backdrop there, image wrong" rather than no backdrop.
    local textured = loadBackdrop()

    lib.print.info(('[ranked] lobby backdrop: %s'):format(textured and backdrop.image or 'image failed, using plain panel'))

    local heading = math.rad(podium.position.w)
    local forward = vector3(-math.sin(heading), math.cos(heading), 0.0)
    local right = vector3(math.cos(heading), math.sin(heading), 0.0)

    local centre = vector3(podium.position.x, podium.position.y, podium.position.z) + forward * backdrop.behind
    local halfWidth = right * (backdrop.width / 2)

    -- Bottom goes well under the floor: the camera looks slightly down, and
    -- anything short of the floor line in view shows as a gap under it.
    local bottom = podium.position.z + (backdrop.bottom or -4.0)
    local top = bottom + backdrop.height

    -- "Left" as the camera sees it, which is where u = 0 goes so the image
    -- is not mirrored.
    local left, rightEdge = centre - halfWidth, centre + halfWidth
    local tl = vector3(left.x, left.y, top)
    local tr = vector3(rightEdge.x, rightEdge.y, top)
    local bl = vector3(left.x, left.y, bottom)
    local br = vector3(rightEdge.x, rightEdge.y, bottom)

    -- A plain stage floor from the backdrop to behind the camera, just above
    -- the ground, so the shot is backdrop + floor and not the dock's concrete
    -- and kerb poking out under the image.
    local stageZ = floorZ(vector3(podium.position.x, podium.position.y, podium.position.z)) + 0.015
    local near = vector3(podium.position.x, podium.position.y, 0.0) - forward * ((podium.distance or 8.0) + 3.0)
    local far = vector3(centre.x, centre.y, 0.0)
    local fl = vector3(far.x - halfWidth.x, far.y - halfWidth.y, stageZ)
    local fr = vector3(far.x + halfWidth.x, far.y + halfWidth.y, stageZ)
    local nl = vector3(near.x - halfWidth.x, near.y - halfWidth.y, stageZ)
    local nr = vector3(near.x + halfWidth.x, near.y + halfWidth.y, stageZ)

    local function drawFloor()
        DrawPoly(fl.x, fl.y, fl.z, fr.x, fr.y, fr.z, nr.x, nr.y, nr.z, 11, 20, 34, 255)
        DrawPoly(fl.x, fl.y, fl.z, nr.x, nr.y, nr.z, nl.x, nl.y, nl.z, 11, 20, 34, 255)
        DrawPoly(nr.x, nr.y, nr.z, fr.x, fr.y, fr.z, fl.x, fl.y, fl.z, 11, 20, 34, 255)
        DrawPoly(nl.x, nl.y, nl.z, nr.x, nr.y, nr.z, fl.x, fl.y, fl.z, 11, 20, 34, 255)
    end

    CreateThread(function()
        while podiumActive and not textured do
            drawFloor()

            DrawPoly(tl.x, tl.y, tl.z, tr.x, tr.y, tr.z, br.x, br.y, br.z, 16, 31, 51, 255)
            DrawPoly(tl.x, tl.y, tl.z, br.x, br.y, br.z, bl.x, bl.y, bl.z, 16, 31, 51, 255)
            DrawPoly(br.x, br.y, br.z, tr.x, tr.y, tr.z, tl.x, tl.y, tl.z, 16, 31, 51, 255)
            DrawPoly(bl.x, bl.y, bl.z, br.x, br.y, br.z, tl.x, tl.y, tl.z, 16, 31, 51, 255)

            Wait(0)
        end

        while podiumActive and textured do
            drawFloor()

            -- Both windings: which face the game treats as the front is not
            -- worth guessing, and a culled quad just vanishes.
            DrawTexturedPoly(tl.x, tl.y, tl.z, tr.x, tr.y, tr.z, br.x, br.y, br.z, 255, 255, 255, 255,
                BACKDROP_TXD, BACKDROP_TEXTURE, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0)
            DrawTexturedPoly(tl.x, tl.y, tl.z, br.x, br.y, br.z, bl.x, bl.y, bl.z, 255, 255, 255, 255,
                BACKDROP_TXD, BACKDROP_TEXTURE, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0)
            DrawTexturedPoly(br.x, br.y, br.z, tr.x, tr.y, tr.z, tl.x, tl.y, tl.z, 255, 255, 255, 255,
                BACKDROP_TXD, BACKDROP_TEXTURE, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0, 1.0)
            DrawTexturedPoly(bl.x, bl.y, bl.z, br.x, br.y, br.z, tl.x, tl.y, tl.z, 255, 255, 255, 255,
                BACKDROP_TXD, BACKDROP_TEXTURE, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 1.0)

            Wait(0)
        end
    end)
end

local function startPodium()
    if podiumActive then
        return
    end

    podiumActive = true

    if config.podium.ipl then
        RequestIpl(config.podium.ipl)
    end

    local podium = config.podium

    -- The game only streams the world around the player. The lobby is rarely
    -- where the player is standing, so without this the camera looked into
    -- unloaded space: a black void with the peds floating in it.
    SetFocusPosAndVel(podium.position.x, podium.position.y, podium.position.z, 0.0, 0.0, 0.0)

    drawBackdropThread()

    podiumCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

    -- Same numbers projectThroughPodiumCamera uses to place the name cards,
    -- so the cards stay under the peds whatever the config says.
    local camCoords = podiumCameraCoords()

    SetCamCoord(podiumCam, camCoords.x, camCoords.y, camCoords.z)
    SetCamRot(podiumCam, podium.cameraPitch or -5.0, 0.0, podium.position.w, 2)
    SetCamFov(podiumCam, podium.fov)
    SetCamActive(podiumCam, true)
    RenderScriptCams(true, true, 500, true, true)
end

local function stopPodium()
    if not podiumActive then
        return
    end

    podiumActive = false

    ClearFocus()

    if podiumCam then
        RenderScriptCams(false, true, 500, true, true)
        DestroyCam(podiumCam, false)

        podiumCam = nil
    end

    clearPodiumPeds()
end

-- Opening a shop/profile tab starts the shop's own preview camera, and
-- closing it switches rendering to the gameplay camera behind the player.
-- The podium camera still exists, so point rendering back at it.
AddEventHandler('shop:previewStopped', function()
    if not podiumActive or not podiumCam then
        return
    end

    local podium = config.podium

    SetFocusPosAndVel(podium.position.x, podium.position.y, podium.position.z, 0.0, 0.0, 0.0)
    SetCamActive(podiumCam, true)
    RenderScriptCams(true, false, 0, true, true)
end)

AddEventHandler('ui:rankedMenuToggled', function(open)
    if open then
        -- The party push happens once, when the player loads. If the NUI has
        -- not mounted yet that message lands nowhere and the panel keeps its
        -- built-in defaults for the rest of the session. Asking for a refresh
        -- on open makes the panel self-heal.
        TriggerServerEvent('ranked:server:refreshUi')

        startPodium()
    else
        stopPodium()
    end
end)

RegisterNetEvent('ranked:client:setPodiumMembers', function(members, slots)
    if podiumActive and type(members) == 'table' then
        buildPodium(members, slots)
    end
end)

exports('stopEmote', function()
    if GetResourceState('shop') == 'started' then
        exports.shop:stopEmote()
    end

    ClearPedTasks(cache.ped)

    return true
end)

AddEventHandler('ranked:playEmoteSlot', function(slotIndex)
    if GetResourceState('shop') ~= 'started' then
        return
    end

    exports.shop:playEmoteSlot(slotIndex)
end)

---@return boolean success
---@return string? error
exports('joinDeathmatch', function()
    local ok, err = lib.callback.await('ranked:server:startLobby', false)

    if not ok then
        return false, err
    end

    ui:closeRankedMenu()

    return true
end)

---@return boolean
exports('returnFromDeathmatch', function()
    TriggerServerEvent('ranked:server:returnToSpawn')
    return true
end)


local PORTAL_RADIUS = 2.0
local PORTAL_POLL_MS = 250

---@type boolean whether the player is currently standing in it
local insidePortal = false

CreateThread(function()
    CoreClient.awaitPlayerLoaded()

    local portal = config.portal

    if not portal or not portal.coords then
        return lib.print.warn('[ranked] config/client.lua has no `portal` entry; the ranked portal is disabled')
    end

    while true do
        local distance = #(GetEntityCoords(cache.ped) - portal.coords)
        local inside = distance <= (portal.radius or PORTAL_RADIUS)

        if inside and not insidePortal then
            insidePortal = true

            if not ui:isRankedMenuVisible() then
                ui:openRankedMenu()
            end
        elseif not inside and insidePortal then
            insidePortal = false
        end

        if distance <= 25.0 then
            DrawMarker(
                1,
                portal.coords.x, portal.coords.y, portal.coords.z - 1.0,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                (portal.radius or PORTAL_RADIUS) * 2.0, (portal.radius or PORTAL_RADIUS) * 2.0, 1.0,
                38, 149, 252, 90,
                false, false, 2, false, nil, nil, false
            )

            Wait(0)
        else
            Wait(PORTAL_POLL_MS)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == cache.resource then
        stopPodium()
    end
end)
