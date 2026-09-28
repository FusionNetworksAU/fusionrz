if IsDuplicityVersion() then return end

---@class CoreClientBootstrap
CoreClient = {}

local isLoaded = false

---@type fun()[]
local loadedCallbacks = {}

---@return boolean
function CoreClient.isPlayerLoaded()
    return isLoaded
end

---@param fn fun()
function CoreClient.onPlayerLoaded(fn)
    if isLoaded then
        return fn()
    end

    loadedCallbacks[#loadedCallbacks + 1] = fn
end

function CoreClient.awaitPlayerLoaded()
    while not isLoaded do
        Wait(50)
    end
end

local function setLoaded(state)
    if isLoaded == state then
        return
    end

    isLoaded = state

    if not state then
        return
    end

    for index = 1, #loadedCallbacks do
        local ok, err = pcall(loadedCallbacks[index])

        if not ok then
            print(('^1[core] onPlayerLoaded callback failed: %s^7'):format(err))
        end
    end

    loadedCallbacks = {}
end

RegisterNetEvent('core:onPlayerLoaded', function()
    setLoaded(true)
end)

RegisterNetEvent('core:onPlayerUnloaded', function()
    setLoaded(false)
end)

CreateThread(function()
    if GetResourceState('core') ~= 'started' then
        while GetResourceState('core') ~= 'started' do
            Wait(200)
        end
    end

    if LocalPlayer.state.isLoaded then
        setLoaded(true)
    end
end)

AddStateBagChangeHandler('isLoaded', ('player:%s'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
    setLoaded(value == true)
end)
