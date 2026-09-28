local playerState = LocalPlayer.state

CreateThread(function()
    while not playerState.uisReady do
        Wait(100)
    end

    while not playerState.isLoaded do
        Wait(100)
    end

    local data = lib.callback.await('ui:server:getChatTagsData', false)

    SendNUIMessage({ action = 'setChatTags', data = data.tags })
    SendNUIMessage({ action = 'setActiveChatTag', data = data.activeTag })
end)

---@param name string
RegisterNUICallback('equipChatTag', function(name, cb)
    local success = lib.callback.await('ui:server:setActiveChatTag', false, name)

    cb(success)
end)

RegisterNUICallback('unequipChatTag', function(_, cb)
    local success = lib.callback.await('ui:server:unsetActiveChatTag', false)

    cb(success)
end)