---@param data table[]
local function setCallingCards(data)
    SendNUIMessage({ action = 'setCallingCards', data = data })
end

exports('setCallingCards', setCallingCards)

---@param id string
local function setEquippedCallingCardId(id)
    SendNUIMessage({ action = 'setEquippedCallingCardId', data = id })
end

exports('setEquippedCallingCardId', setEquippedCallingCardId)

---@param data table[]
local function setCallingCardCategories(data)
    SendNUIMessage({ action = 'setCallingCardCategories', data = data })
end

exports('setCallingCardCategories', setCallingCardCategories)

---@param cardId string
RegisterNUICallback('equipCallingCard', function(cardId, cb)
    local success = lib.callback.await('callingcards:server:equipCardId', false, cardId)

    cb(success)
end)