local audioIdCounter = 1

---@type table<integer, promise>
local audioPromises = {}

---@param audioId number
---@param cb function
RegisterNUICallback('onAudioEnded', function(audioId, cb)
    local p = audioPromises[audioId]
    if p then
        audioPromises[audioId] = nil
        p:resolve()
    end
    cb(true)
end)

---@async
---@param name string
---@param volume number
---@param shouldAwait boolean
---@return integer
exports('playAudio', function(name, volume, shouldAwait)
    local audioId = audioIdCounter
    audioIdCounter += 1

    ---@type promise?
    local p = nil
    if shouldAwait then
        p = promise:new()
        audioPromises[audioId] = p
    end

    SendNUIMessage({
        action = 'playAudio',
        data = {
            file = name,
            volume = lib.math.clamp(volume or 1.0, 0.0, 1.0),
            audioId = audioId,
        },
    })

    if p then
        Citizen.Await(p)
    end

    return audioId
end)

---@param audioId integer
exports('stopAudio', function(audioId)
    SendNUIMessage({
        action = 'stopAudio',
        data = audioId,
    })
end)

local function stopAllAudio()
    SendNUIMessage({
        action = 'stopAllAudio',
    })
end

exports('stopAllAudio', stopAllAudio)

---@param cb function
RegisterNUICallback('stopAudio', function(_, cb)
    stopAllAudio()
    cb(true)
end)

---@param name string
---@param volume number
---@param fadeInMs number?
---@return integer audioId
exports('playLoopingAudio', function(name, volume, fadeInMs)
    local audioId = audioIdCounter
    audioIdCounter += 1

    SendNUIMessage({
        action = 'playAudio',
        data = {
            file = name,
            volume = lib.math.clamp(volume or 1.0, 0.0, 1.0),
            audioId = audioId,
            loop = true,
            fadeIn = fadeInMs,
        },
    })

    return audioId
end)

---@param audioId integer
---@param fadeOutMs number?
exports('stopLoopingAudio', function(audioId, fadeOutMs)
    SendNUIMessage({
        action = 'stopAudio',
        data = {
            audioId = audioId,
            fadeOut = fadeOutMs,
        },
    })
end)

---@param name string
---@param volume number
---@param pan number
---@param fadeInMs number?
---@return integer audioId
exports('playSpatialAudio', function(name, volume, pan, fadeInMs)
    local audioId = audioIdCounter
    audioIdCounter += 1

    SendNUIMessage({
        action = 'playSpatialAudio',
        data = {
            file = name,
            audioId = audioId,
            volume = lib.math.clamp(volume or 0.0, 0.0, 1.0),
            pan = lib.math.clamp(pan or 0.0, -1.0, 1.0),
            fadeIn = fadeInMs,
        },
    })

    return audioId
end)

---@param audioId integer
---@param volume number
---@param pan number
exports('updateSpatialAudio', function(audioId, volume, pan)
    SendNUIMessage({
        action = 'updateSpatialAudio',
        data = {
            audioId = audioId,
            volume = lib.math.clamp(volume or 0.0, 0.0, 1.0),
            pan = lib.math.clamp(pan or 0.0, -1.0, 1.0),
        },
    })
end)

---@param audioId integer
---@param fadeOutMs number?
exports('stopSpatialAudio', function(audioId, fadeOutMs)
    SendNUIMessage({
        action = 'stopSpatialAudio',
        data = {
            audioId = audioId,
            fadeOut = fadeOutMs,
        },
    })
end)