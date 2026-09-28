local shared = require 'config.shared' ---@type LevelsSharedConfig

local ui = exports.ui
local misc = exports.misc
local localpeds = exports.localpeds
local playerState = LocalPlayer.state

local REAPER = vec4(-6180.9165, -5162.1455, 933.8799, 143.7250)

---@type CareerLevelState?
local state

local busy = false
local promptShown = false

---@type boolean?
local answer

---@type table<string, string>
local DENY = {
    level = ('Reach level %d first'):format(shared.maxLevel),
    max_prestige = 'You are at max prestige',
    in_match = 'Visit the Reaper at spawn',
}

---@return boolean
local function canPrestige()
    return state ~= nil and state.level >= state.maxLevel and state.prestige < state.maxPrestige
end

local keybind

---@param show boolean
local function setPrompt(show)
    if show == promptShown then
        return
    end
    promptShown = show
    if not show then
        ui:hideTextUI()
    elseif canPrestige() then
        ui:setTextUI({ title = 'PRESTIGE', subtitle = ('Press [%s] to be reborn'):format(keybind.currentKey) })
    elseif state and state.prestige >= state.maxPrestige then
        ui:setTextUI({ title = 'THE REAPER', subtitle = DENY.max_prestige })
    else
        ui:setTextUI({ title = 'THE REAPER', subtitle = ('Reach level %d to be reborn'):format(shared.maxLevel) })
    end
end

local reaperPoint = lib.points.new({
    coords = REAPER.xyz,
    distance = 2.5,
    onEnter = function()
        if not busy then
            setPrompt(true)
        end
    end,
    onExit = function()
        setPrompt(false)
    end,
})

---@param level integer
---@param xp integer
---@param prestige integer
RegisterNetEvent('levels:client:state', function(level, xp, prestige)
    state = shared.buildState(level, xp, prestige)
    if promptShown then
        promptShown = false
        setPrompt(true)
    end
end)

---ui has no dedicated level-up surface -- setCareerLevel (driven by the
---state event above) only redraws the bar -- so the moment itself is worth
---one notification, or crossing a level passes silently.
---@param level integer
---@param gained integer
RegisterNetEvent('levels:client:levelUp', function(level, gained)
    ui:notify({
        type = 'success',
        text = gained > 1 and ('Level %d (+%d levels)'):format(level, gained) or ('Level %d'):format(level),
        duration = 5000,
    })
end)

---@param confirm boolean
AddEventHandler('ui:prestigeAnswer', function(confirm)
    answer = confirm
end)

local function prestige()
    busy = true
    setPrompt(false)
    local err = lib.callback.await('levels:server:canPrestige', false)
    if err then
        ui:notify({ type = 'error', text = DENY[err] })
        busy = false
        return
    end
    answer = nil
    ui:setPrestigeOffer({ next = state.prestige + 1, seconds = shared.answerTtlSeconds })
    local deadline = GetGameTimer() + shared.answerTtlSeconds * 1000
    while answer == nil and GetGameTimer() < deadline do
        Wait(100)
    end
    if answer == nil then
        ui:setPrestigeOffer(nil)
    elseif answer then
        misc:startPrestigeCutscene()
        err = lib.callback.await('levels:server:prestige', false)
        if err then
            ui:notify({ type = 'error', text = DENY[err] })
        else
            ui:setPrestigeSuccess(state.prestige)
        end
    end
    busy = false
    if reaperPoint.inside then
        setPrompt(true)
    end
end

keybind = lib.addKeybind({
    name = 'levels_prestige',
    description = 'Talk to the Reaper',
    defaultKey = 'E',
    onPressed = function()
        if promptShown and canPrestige() and not busy then
            CreateThread(prestige)
        end
    end,
})

CreateThread(function()
    while not playerState.isLoaded do
        Wait(500)
    end
    localpeds:CreatePedPoint({
        model = 'ig_chrisformage',
        coords = REAPER,
        renderDistance = 80.0,
        scenario = { name = 'WORLD_HUMAN_STAND_IMPATIENT' },
    })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == cache.resource then
        setPrompt(false)
        if busy then
            ui:setPrestigeOffer(nil)
        end
    end
end)
