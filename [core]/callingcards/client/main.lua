local categories = require 'data.categories'

local core = exports.core
local ui = exports.ui

local playerState = LocalPlayer.state

---@type CustomCallingCard[]
local customCards = {}

local isLoaded = false

---@return CallingCardEntry[]
local function buildCards()
    ---@type table<string, true>
    local usableCardIds = {}

    for _, cardId in pairs(core:GetUsableTypeIds('calling_cards')) do
        usableCardIds[cardId] = true
    end

    ---@type CallingCardEntry[]
    local cards = {}

    for cardId, cardData in pairs(core:GetAllCards()) do
        local isUnlocked = usableCardIds[cardId] == true

        if cardData.type ~= 'gang' or isUnlocked then
            cards[#cards + 1] = {
                id = cardId,
                label = cardData.name,
                description = cardData.description,
                category = cardData.type or 'general',
                isUnlocked = isUnlocked,
            }
        end
    end

    for _, customCard in pairs(customCards) do
        cards[#cards + 1] = {
            id = customCard.id,
            label = customCard.label,
            description = 'Custom calling card',
            category = 'custom',
            isUnlocked = true,
        }
    end

    return cards
end

local function sendCards()
     while not playerState.uisReady do
        Wait(0)
    end

    ui:setCallingCards(buildCards())
end

local function refresh()
    while not playerState.uisReady do
        Wait(0)
    end

    ui:setCallingCardCategories(categories)
    ui:setCallingCards(buildCards())
    ui:setEquippedCallingCardId(playerState.calling_card)
end

---@param affectedTypeIds string[]?
---@return boolean
local function areCardsAffected(affectedTypeIds)
    if not affectedTypeIds then
        return true
    end

    for _, typeId in pairs(affectedTypeIds) do
        if core:GetCardItem(typeId) then
            return true
        end
    end

    return false
end

---@param affectedTypeIds string[]?
AddEventHandler('core:onInventoryUpdated', function(affectedTypeIds)
    if not isLoaded or not areCardsAffected(affectedTypeIds) then
        return
    end

    sendCards()
end)

---@param cards CustomCallingCard[]
RegisterNetEvent('callingcards:setCustomCards', function(cards)
    customCards = cards

    if isLoaded then
        sendCards()
    end
end)

---@param value string
AddStateBagChangeHandler('calling_card', ('player:%s'):format(cache.serverId), function(_, _, value)
    if not isLoaded then
        return
    end

    ui:setEquippedCallingCardId(value)
end)

---@param resourceName string
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= 'ui' or not isLoaded then
        return
    end

    refresh()
end)

CreateThread(function()
    while not playerState.isLoaded do
        Wait(0)
    end

    while not core:AreItemsReady() do
        Wait(50)
    end

    isLoaded = true

    refresh()
end)
