---Takes the clothing pictures for /clothingshots (server/thumbnails.lua).
---
---A plain freemode ped hangs in the sky in front of a green panel, away from
---everything; for each item it is put in a neutral base outfit plus the
---piece, the camera is framed for that slot, and ui grabs the game frame
---(ui exports captureGame: square crop, green keyed to transparent).

---Well clear of the shop's own preview spot (Tuning.previewCoords).
local SPOT = vector4(-3600.0, -1300.0, 1600.0, 0.0)

local MODEL = `mp_m_freemode_01`

---Per slot: `z` is the height looked at, relative to the ped's origin (about
---the hips), `distance` how far in front the camera stands, `fov` the
---vertical field of view (the shot is a square of the full height, so it is
---the horizontal one too), `turn` degrees the ped is turned from the camera.
local FRAMING = {
    shirts    = { z = 0.25,  distance = 1.55, fov = 42, turn = 0 },
    arms      = { z = 0.15,  distance = 1.65, fov = 46, turn = 0 },
    vests     = { z = 0.22,  distance = 1.50, fov = 40, turn = 0 },
    chains    = { z = 0.42,  distance = 0.85, fov = 32, turn = 0 },
    bags      = { z = 0.22,  distance = 1.55, fov = 42, turn = 180 },
    pants     = { z = -0.45, distance = 1.60, fov = 44, turn = 0 },
    shoes     = { z = -0.88, distance = 0.95, fov = 34, turn = 35 },
    masks     = { z = 0.66,  distance = 0.75, fov = 30, turn = 0 },
    hats      = { z = 0.72,  distance = 0.85, fov = 32, turn = 20 },
    glasses   = { z = 0.66,  distance = 0.60, fov = 28, turn = 20 },
    watches   = { z = 0.02,  distance = 0.70, fov = 28, turn = 90 },
    bracelets = { z = 0.02,  distance = 0.70, fov = 28, turn = 270 },
}

local DEFAULT_FRAMING = { z = 0.0, distance = 2.6, fov = 50, turn = 0 }

local shooting = false

---@type table<string, boolean?> item id -> save result from the server
local saved = {}

RegisterNetEvent('shop:client:thumbnailSaved', function(itemId, ok)
    saved[itemId] = ok == true
end)

RegisterNetEvent('shop:client:thumbnailNotice', function(kind, text)
    exports.ui:notify({ type = kind, text = text, duration = 6000 })
end)

---@param ped integer
local function dressBase(ped)
    -- The plain default ped (every component 0), no props: the piece being
    -- photographed is the only thing that changes between shots.
    for component = 0, 11 do
        SetPedComponentVariation(ped, component, 0, 0, 0)
    end

    ClearAllPedProps(ped)
end

---@param ped integer
---@param apply { components: table[], props: table[] }
local function dressItem(ped, apply)
    for _, part in ipairs(apply.components or {}) do
        local id, drawable, texture = part.component_id, part.drawable or 0, part.texture or 0

        if IsPedComponentVariationValid(ped, id, drawable, texture) then
            SetPedComponentVariation(ped, id, drawable, texture, 0)
        elseif IsPedComponentVariationValid(ped, id, drawable, 0) then
            SetPedComponentVariation(ped, id, drawable, 0, 0)
        end
    end

    for _, prop in ipairs(apply.props or {}) do
        if (prop.drawable or -1) >= 0 then
            SetPedPropIndex(ped, prop.prop_id, prop.drawable, prop.texture or 0, true)
        end
    end
end

---Until the new clothes have streamed in, or 3s.
---@param ped integer
local function awaitStreaming(ped)
    local deadline = GetGameTimer() + 3000

    Wait(150)

    while not HaveAllStreamingRequestsCompleted(ped) and GetGameTimer() < deadline do
        Wait(50)
    end

    -- A couple of frames for the new textures to actually draw.
    Wait(250)
end

---@param jobs { id: string, slot: string, apply: table }[]
RegisterNetEvent('shop:client:shootClothing', function(jobs)
    if shooting or type(jobs) ~= 'table' then
        return
    end

    shooting = true

    pcall(function() exports.ui:closeRankedMenu() end)
    pcall(function() exports.ui:closeMenu() end)

    exports.ui:notify({ type = 'info', text = ('Photographing %d items, hold still...'):format(#jobs), duration = 5000 })

    DoScreenFadeOut(300)
    Wait(400)

    -- Daylight, so every shot is lit the same.
    NetworkOverrideClockTime(12, 0, 0)

    SetFocusPosAndVel(SPOT.x, SPOT.y, SPOT.z, 0.0, 0.0, 0.0)
    lib.requestModel(MODEL, 10000)

    local ped = CreatePed(4, MODEL, SPOT.x, SPOT.y, SPOT.z, SPOT.w, false, false)

    SetModelAsNoLongerNeeded(MODEL)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetPedCanRagdoll(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedHeadBlendData(ped, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, false)

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)

    -- Green panel behind the ped, drawn every frame; the capture keys it out.
    local panel = { active = true }

    CreateThread(function()
        while panel.active do
            HideHudAndRadarThisFrame()

            if panel.corners then
                local c = panel.corners

                DrawPoly(c[1].x, c[1].y, c[1].z, c[2].x, c[2].y, c[2].z, c[3].x, c[3].y, c[3].z, 0, 255, 0, 255)
                DrawPoly(c[1].x, c[1].y, c[1].z, c[3].x, c[3].y, c[3].z, c[4].x, c[4].y, c[4].z, 0, 255, 0, 255)
                DrawPoly(c[3].x, c[3].y, c[3].z, c[2].x, c[2].y, c[2].z, c[1].x, c[1].y, c[1].z, 0, 255, 0, 255)
                DrawPoly(c[4].x, c[4].y, c[4].z, c[3].x, c[3].y, c[3].z, c[1].x, c[1].y, c[1].z, 0, 255, 0, 255)
            end

            Wait(0)
        end
    end)

    DoScreenFadeIn(300)

    local width, height = GetActiveScreenResolution()
    local side = height / width
    -- Square from the middle of the frame, full height.
    local crop = { x = (1 - side) / 2, y = 0.0, w = side, h = 1.0 }

    local failed = 0

    for index, job in ipairs(jobs) do
        local frame = FRAMING[job.slot] or DEFAULT_FRAMING

        -- The camera looks north (+y) at the ped from the south; the ped is
        -- turned away from facing it by `turn`.
        SetEntityHeading(ped, (180.0 + frame.turn) % 360.0)

        dressBase(ped)
        dressItem(ped, job.apply or {})

        local target = vector3(SPOT.x, SPOT.y, SPOT.z + frame.z)
        local camPos = vector3(SPOT.x, SPOT.y - frame.distance, target.z)

        SetCamCoord(cam, camPos.x, camPos.y, camPos.z)
        PointCamAtCoord(cam, target.x, target.y, target.z)
        SetCamFov(cam, frame.fov + 0.0)

        -- Panel 1.2m behind the ped, wide and tall enough to fill the shot.
        local back = SPOT.y + 1.2
        local half = 3.0

        panel.corners = {
            vector3(SPOT.x - half, back, target.z + half),
            vector3(SPOT.x + half, back, target.z + half),
            vector3(SPOT.x + half, back, target.z - half),
            vector3(SPOT.x - half, back, target.z - half),
        }

        awaitStreaming(ped)

        local image, err = exports.ui:captureGame(crop, 512, 0.9)

        if image then
            saved[job.id] = nil
            TriggerLatentServerEvent('shop:server:saveThumbnail', 250000, job.id, image)

            local deadline = GetGameTimer() + 20000

            while saved[job.id] == nil and GetGameTimer() < deadline do
                Wait(50)
            end

            if saved[job.id] ~= true then
                failed += 1
            end
        else
            failed += 1
            lib.print.warn(('[shop] could not photograph %s: %s'):format(job.id, err or 'unknown'))
        end

        if index % 10 == 0 then
            exports.ui:notify({ type = 'info', text = ('Photographed %d / %d'):format(index, #jobs), duration = 2500 })
        end
    end

    DoScreenFadeOut(300)
    Wait(350)

    panel.active = false

    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(cam, false)
    DeleteEntity(ped)
    ClearFocus()
    NetworkClearClockTimeOverride()

    DoScreenFadeIn(300)

    shooting = false

    TriggerServerEvent('shop:server:thumbnailsDone', failed)
end)
