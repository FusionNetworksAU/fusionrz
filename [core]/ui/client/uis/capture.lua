---Captures the game frame through the NUI page (web/build/assets/fnrz-capture.js).
---Used by shop's clothing thumbnail tool; the page crops, keys out the green
---backdrop and answers with a WebP data URI.

---@type table<integer, promise>
local pending = {}
local nextId = 0

---@param crop { x: number, y: number, w: number, h: number } fractions of the screen
---@param size integer? output width and height in pixels
---@param quality number? 0..1
---@return string? image data URI, nil on failure
---@return string? error
local function captureGame(crop, size, quality)
    nextId += 1

    local id = nextId
    local p = promise.new()

    pending[id] = p

    SendNUIMessage({
        action = 'fnrzCapture',
        data = { id = id, crop = crop, size = size or 512, quality = quality or 0.9 },
    })

    -- The page answers within a few frames; this only guards a page that
    -- never loaded the capture script.
    SetTimeout(10000, function()
        if pending[id] then
            pending[id] = nil
            p:resolve({ error = 'capture timed out' })
        end
    end)

    local result = Citizen.Await(p)

    return result.image, result.error
end

exports('captureGame', captureGame)

---@param data { id: integer, image: string?, error: string? }
RegisterNUICallback('fnrzCaptured', function(data, cb)
    cb(1)

    local p = data and pending[data.id]

    if not p then
        return
    end

    pending[data.id] = nil
    p:resolve({ image = data.image, error = data.error })
end)
