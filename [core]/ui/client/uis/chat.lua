local playerState = LocalPlayer.state

---@param isVisible boolean
local function setChatInputVisible(isVisible)
    SendNUIMessage({ action = 'setChatInputVisible', data = isVisible })

    if isVisible then
        SetNuiFocus(true, true)
    elseif not IsRankedOverlayFocused() then
        SetNuiFocus(false, false)
    end
end

exports('setChatInputVisible', setChatInputVisible)

---@param message GameChatMessage
local function addChatMessage(message)
    SendNUIMessage({ action = 'addChatMessage', data = message })
end

exports('addChatMessage', addChatMessage)

---@param data { mode: ChatVisibilityMode, fromUserInteraction: boolean }
local function setChatMessagesMode(data)
    SendNUIMessage({ action = 'setChatMessagesMode', data = data })
end

exports('setChatMessagesMode', setChatMessagesMode)

---The NUI's suggestion list reads `params.length` and `params.map` with no
---guard, so a command registered without params (/warmute, /clearchat) threw
---inside React the moment "/" was typed and took the whole UI down. Every
---suggestion is filled out here, whichever resource it came from.
---@param suggestion table?
---@return table?
local function normaliseSuggestion(suggestion)
    if type(suggestion) ~= 'table' or type(suggestion.name) ~= 'string' then
        return nil
    end

    local params = {}

    if type(suggestion.params) == 'table' then
        for index = 1, #suggestion.params do
            local param = suggestion.params[index]

            if type(param) == 'table' then
                params[#params + 1] = {
                    name = tostring(param.name or ''),
                    help = tostring(param.help or ''),
                }
            end
        end
    end

    local name = suggestion.name

    -- Some senders (ox_lib, the stock chat events) include the slash, others
    -- pass the bare command name; the list filters on the slash.
    if name:sub(1, 1) ~= '/' then
        name = '/' .. name
    end

    return {
        name = name,
        help = tostring(suggestion.help or ''),
        params = params,
    }
end

---Suggestions the NUI already has, name -> whether it came with help text.
---The NUI appends without checking, and the same command arrives from more
---than one place (the command scan in gamechat, ox_lib's own broadcast, the
---hand-written list), so it would be listed two or three times.
---@type table<string, boolean>
local knownSuggestions = {}

---Drops a suggestion the list already has, unless this one has help text
---and the stored one does not; then the old one is removed so this replaces it.
---@param suggestion table
---@return boolean keep
local function claimSuggestion(suggestion)
    local hasHelp = suggestion.help ~= '' or #suggestion.params > 0
    local known = knownSuggestions[suggestion.name]

    if known ~= nil then
        if known or not hasHelp then
            return false
        end

        SendNUIMessage({ action = 'removeChatSuggestion', data = suggestion.name })
    end

    knownSuggestions[suggestion.name] = hasHelp

    return true
end

---@param data GameChatSuggestion
local function addChatSuggestion(data)
    data = normaliseSuggestion(data)

    if not data then
        return
    end

    while not playerState.uisReady do
        Wait(100)
    end

    if not claimSuggestion(data) then
        return
    end

    SendNUIMessage({ action = 'addChatSuggestion', data = data })
end

exports('addChatSuggestion', addChatSuggestion)

---@param data GameChatSuggestion[]
local function addChatSuggestions(data)
    if type(data) ~= 'table' then
        return
    end

    while not playerState.uisReady do
        Wait(100)
    end

    local suggestions = {}

    for index = 1, #data do
        local suggestion = normaliseSuggestion(data[index])

        if suggestion and claimSuggestion(suggestion) then
            suggestions[#suggestions + 1] = suggestion
        end
    end

    if #suggestions > 0 then
        SendNUIMessage({ action = 'addChatSuggestions', data = suggestions })
    end
end

exports('addChatSuggestions', addChatSuggestions)

---@param name string
local function removeChatSuggestion(name)
    if type(name) ~= 'string' then
        return
    end

    if name:sub(1, 1) ~= '/' then
        name = '/' .. name
    end

    while not playerState.uisReady do
        Wait(100)
    end

    knownSuggestions[name] = nil

    SendNUIMessage({ action = 'removeChatSuggestion', data = name })
end

-- A reloaded page starts with an empty list, so everything is sendable again.
AddEventHandler('uis:onReady', function()
    knownSuggestions = {}
end)

exports('removeChatSuggestion', removeChatSuggestion)

local function clearChatMessages()
    SendNUIMessage({ action = 'clearChatMessages', data = {} })
end

exports('clearChatMessages', clearChatMessages)

---@param modes GameChatMode[]
local function setChatModes(modes)
    SendNuiMessage(json.encode({
        action = 'setChatModes',
        data = modes
    }, { sort_keys = true }))
end

exports('setChatModes', setChatModes)

---@param mode GameChatMode
local function addChatMode(mode)
    SendNUIMessage({ action = 'addChatMode', data = mode })
end

exports('addChatMode', addChatMode)

---@param name string
local function removeChatMode(name)
    SendNUIMessage({ action = 'removeChatMode', data = name })
end

exports('removeChatMode', removeChatMode)

local function clearChatModes()
    SendNUIMessage({ action = 'clearChatModes', data = {} })
end

exports('clearChatModes', clearChatModes)

---@param mode string
local function setCurrentChatMode(mode)
    SendNUIMessage({ action = 'setCurrentChatMode', data = mode })
end

exports('setCurrentChatMode', setCurrentChatMode)

RegisterNUICallback('hideChatInput', function(_, cb)
    setChatInputVisible(false)

    cb(1)
end)

RegisterNUICallback('getMentionablePlayers', function(_, cb)
    cb(exports.gamechat:getMentionablePlayers())
end)

local function usePreSecurityBehavior()
    -- use `setr sysresource_chat_disableOriginSecurityChecks true` on the server to allow non secure execution
    -- of commands and events, `setr` will also disallow clients to change it
    return GetConvar('sysresource_chat_disableOriginSecurityChecks', 'true') == 'true'
end

---@param requestData table
---@param cb function
RegisterRawNuiCallback('sendChatMessage', function(requestData, cb)
    -- A raw callback must always answer, with a status: an early return left
    -- the page's request hanging, and a reply without one can be refused.
    local function reply(success)
        cb({
            status = 200,
            headers = { ['Content-Type'] = 'application/json' },
            body = json.encode({ success = success }),
        })
    end

    local resource = requestData.resource
    local securityDisabled = usePreSecurityBehavior()

    -- only allow actual resources to call in here
    if resource == nil and not securityDisabled then
        return reply(false)
    end

    setChatInputVisible(false)

    local data = json.decode(requestData.body or '')

    if type(data) ~= 'table' or type(data.text) ~= 'string' then
        return reply(false)
    end

    if data.text:sub(1, 1) == '/' then
        -- Only this resource's NUI page can execute commands
        if resource == cache.resource or securityDisabled then
            ExecuteCommand(data.text:sub(2))
        end
    else
        TriggerServerEvent('gamechat:server:messageRequest', data)
    end

    reply(true)
end)