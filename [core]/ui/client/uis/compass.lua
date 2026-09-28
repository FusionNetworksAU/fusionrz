local env = require '@core.modules.env'

local playerState = LocalPlayer.state

local isVisible = false
local lastHeading = 1

local isThreadActive = false

---@param heading number
local function setCompassHeading(heading)
    SendNUIMessage({ action = 'setCompassHeading', data = heading })
end

exports('setCompassHeading', setCompassHeading)

local function startHeadingThread()
    if isThreadActive then
        return
    end

    isThreadActive = true

    CreateThread(function()
        while not playerState.uisReady or not playerState.isLoaded do
            Wait(100)
        end

        while isVisible do
            local camRot = GetGameplayCamRot(0)

            local heading = lib.math.round(360.0 - ((camRot.z + 360.0) % 360.0))
            if heading == 360 then heading = 0 end

            if heading ~= lastHeading then
                setCompassHeading(heading)
            end

            lastHeading = heading

            Wait(0)
        end

        isThreadActive = false
    end)
end

---@param visible boolean
local function setCompassVisible(visible)
    SendNUIMessage({ action = 'setCompassVisible', data = visible })
    isVisible = visible

    if isVisible then
        startHeadingThread()
    end
end

exports('setCompassVisible', setCompassVisible)

if env.getEnv() ~= 'development' then
    return
end

RegisterCommand('compass', function()
    setCompassVisible(not isVisible)
end, false)