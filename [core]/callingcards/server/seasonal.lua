---Seasonal windows and custom cards.
---
---Two things that both answer "may this player wear this card", but for
---different reasons:
---
---  * a seasonal card is owned permanently and wearable only inside its
---    window, so last year's event card goes back in the drawer rather than
---    being taken away;
---  * a custom card is not in the catalogue at all — it is granted to one
---    player, so ownership cannot be looked up in core's items.

Callingcards = Callingcards or {}

local core = exports.core

---Seasonal windows, keyed by card id. `from`/`to` are os.time values; a
---window with no `to` never closes.
---@type table<string, { from: integer, to: integer? }>
local windows = {}

---@type table<integer, CustomCallingCard[]> userId -> cards
local customCards = {}

-- -------------------------------------------------------------- seasonal ----

---@param cardId string
---@param from integer
---@param to integer?
function Callingcards.registerWindow(cardId, from, to)
    windows[cardId] = { from = from, to = to }
end

---A card with no window is always available: most cards are not seasonal,
---and requiring every one of them to be registered would make the common
---case the fragile one.
---@param cardId string
---@return boolean
function Callingcards.isAvailable(cardId)
    local window = windows[cardId]

    if not window then
        return true
    end

    local now = os.time()

    if now < window.from then
        return false
    end

    return window.to == nil or now <= window.to
end

---@param cardId string
---@return { from: integer, to: integer? }?
function Callingcards.getWindow(cardId)
    return windows[cardId]
end

exports('RegisterSeasonalWindow', Callingcards.registerWindow)
exports('IsCardAvailable', Callingcards.isAvailable)

-- ---------------------------------------------------------------- custom ----

---@class CustomCallingCard
---@field id string
---@field label string

---@param source Source
---@return integer? userId
local function getUserId(source)
    local data = core:GetPlayerData(source)

    return data and data.userId or nil
end

---@param source Source
---@param cardId string
---@return boolean
function Callingcards.isCustomCard(source, cardId)
    local userId = getUserId(source)
    local owned = userId and customCards[userId]

    if not owned then
        return false
    end

    for index = 1, #owned do
        if owned[index].id == cardId then
            return true
        end
    end

    return false
end

---@param source Source
function Callingcards.pushCustomCards(source)
    local userId = getUserId(source)

    TriggerClientEvent('callingcards:setCustomCards', source, userId and customCards[userId] or {})
end

---@param source Source
---@param cards CustomCallingCard[]
---@return boolean
exports('SetCustomCards', function(source, cards)
    local userId = getUserId(source)

    if not userId or type(cards) ~= 'table' then
        return false
    end

    customCards[userId] = cards

    Callingcards.pushCustomCards(source)

    return true
end)

---@param source Source
---@param card CustomCallingCard
---@return boolean
exports('GrantCustomCard', function(source, card)
    local userId = getUserId(source)

    if not userId or type(card) ~= 'table' or type(card.id) ~= 'string' then
        return false
    end

    customCards[userId] = customCards[userId] or {}

    for index = 1, #customCards[userId] do
        if customCards[userId][index].id == card.id then
            return true
        end
    end

    customCards[userId][#customCards[userId] + 1] = {
        id = card.id,
        label = card.label or card.id,
    }

    Callingcards.pushCustomCards(source)

    return true
end)

---Held in memory only: nothing persists custom cards yet, so whatever
---granted one is responsible for granting it again next session. Cleared on
---drop so a reused userId slot cannot inherit someone else's.
AddEventHandler('core:server:onPlayerDropped', function(_, userId)
    customCards[userId] = nil
end)
