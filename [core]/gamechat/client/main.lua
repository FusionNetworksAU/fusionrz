local playerState = LocalPlayer.state

local ui = exports.ui

local isLoaded = playerState.isLoaded
local uisReady = playerState.uisReady
local warAnnouncementsMuted = false

---@type table<string, ChatVisibilityMode>
local CHAT_HIDE_STATES = {
    SHOW_WHEN_ACTIVE = 'showOnNewThenHide',
    ALWAYS_SHOW = 'always',
    ALWAYS_HIDE = 'hide'
}

---@type string
local KVP_KEY = 'fusionrz_v5:chat_state'

---@type string
local chatHideState = GetResourceKvpString(KVP_KEY) or CHAT_HIDE_STATES.SHOW_WHEN_ACTIVE

---@param state string
---@return boolean isValid
local function validateChatState(state)
    for k, v in pairs(CHAT_HIDE_STATES) do
        if state == v then
            return true
        end
    end

    return false
end

if not validateChatState(chatHideState) then
    chatHideState = CHAT_HIDE_STATES.SHOW_WHEN_ACTIVE
end

local lastChatHideState = nil
local origChatHideState = nil
local isFirstHide = true

---@param forceSetToGame boolean
local function refreshChatModes(forceSetToGame)
    local modes = lib.callback.await('gamechat:server:getAllowedModes', false)
    ui:setChatModes(modes)

    if forceSetToGame then
        ui:setCurrentChatMode('game')
    end
end

---@return ChatVisibilityMode
local function getChatStatePreference()
    local kvpValue = GetResourceKvpString(KVP_KEY)

    if not validateChatState(kvpValue) then
        return CHAT_HIDE_STATES.SHOW_WHEN_ACTIVE
    end

    return kvpValue
end

exports('getChatStatePreference', getChatStatePreference)

---@param state ChatVisibilityMode
---@param writeToKvp? boolean
local function setChatState(state, writeToKvp)
    if not state or not validateChatState(state) then
        return
    end

    chatHideState = state
    isFirstHide = false

    if not writeToKvp then
        return
    end

    SetResourceKvp(KVP_KEY, chatHideState)
end

exports('setChatState', setChatState)

local function restoreChatState()
    local lastSavedPreference = getChatStatePreference()
    setChatState(lastSavedPreference, false)
end

exports('restoreChatState', restoreChatState)

---@param message string
RegisterNetEvent('__cfx_internal:serverPrint', function(message)
    print(message)
end)

---@param message GameChatMessage
RegisterNetEvent('gamechat:addMessage', function(message)
    if warAnnouncementsMuted and message.action then
        return
    end

    ui:addChatMessage(message)
end)

RegisterNetEvent('gamechat:toggleWarMute', function()
    warAnnouncementsMuted = not warAnnouncementsMuted
    ui:notify({ type = 'info', text = warAnnouncementsMuted and 'War announcements muted' or 'War announcements unmuted' })
end)

---@param suggestion GameChatSuggestion
RegisterNetEvent('gamechat:addSuggestion', function(suggestion)
    ui:addChatSuggestion(suggestion)
end)

---@param suggestions GameChatSuggestion[]
RegisterNetEvent('gamechat:addSuggestions', function(suggestions)
    ui:addChatSuggestions(suggestions)
end)

---@param name string
RegisterNetEvent('gamechat:removeSuggestion', function(name)
    ui:removeChatSuggestion(name)
end)

RegisterNetEvent('gamechat:clearMessages', function()
    ui:clearChatMessages()
end)

---@param mode GameChatMode
RegisterNetEvent('gamechat:addMode', function(mode)
    ui:addChatMode(mode)
end)

---@param name string
RegisterNetEvent('gamechat:removeMode', function(name)
    ui:removeChatMode(name)
end)

---@param forceSetToGame boolean
RegisterNetEvent('gamechat:refreshModes', function(forceSetToGame)
    refreshChatModes(forceSetToGame)
end)

---@return { userId: number, username: string }[] players
exports('getMentionablePlayers', function()
    return lib.callback.await('gamechat:server:getMentionablePlayers', false)
end)

local keybind = lib.addKeybind({
    name = 'openChat',
    description = 'Open the text chat',
    defaultKey = 't',
    onPressed = function()
        ui:setChatInputVisible(true)
    end
})

---@param disabled boolean
exports('setChatInputDisabled', function(disabled)
    keybind:disable(disabled)
end)

CreateThread(function()
    SetTextChatEnabled(false)

    while not uisReady do
        Wait(100)
    end

    while not isLoaded do
        Wait(100)
    end

    refreshChatModes(false)

    while true do
        local forceHide = IsScreenFadedOut() or IsPauseMenuActive()
        local wasForceHide = false

        if chatHideState ~= CHAT_HIDE_STATES.ALWAYS_HIDE then
            if forceHide then
                origChatHideState = chatHideState
                chatHideState = CHAT_HIDE_STATES.ALWAYS_HIDE
            end
        elseif not forceHide and origChatHideState ~= nil then
            chatHideState = origChatHideState
            origChatHideState = nil
            wasForceHide = true
        end

        if chatHideState ~= lastChatHideState then
            lastChatHideState = chatHideState

            ui:setChatMessagesMode({
                mode = chatHideState,
                fromUserInteraction = not forceHide and not isFirstHide and not wasForceHide
            })

            isFirstHide = false
        end

        Wait(250)
    end
end)

AddStateBagChangeHandler('isLoaded', ('player:%s'):format(cache.serverId), function(_, _, value)
    isLoaded = value
end)

AddStateBagChangeHandler('uisReady', ('player:%s'):format(cache.serverId), function(_, _, value)
    uisReady = value
end)