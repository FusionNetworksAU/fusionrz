---Calling cards: which one a player wears, and whether they may.
---
---Ownership is core's — a card is an item in the `calling_cards` category —
---so nothing is duplicated here. What this owns is the equipped choice: it
---lives in core metadata under CARD_METADATA_KEY (shared/main.lua) so it
---survives a reconnect, and is mirrored onto the player statebag so every
---OTHER client can draw the right card over their head without asking.

local core = exports.core

---Filled by server/seasonal.lua, which the manifest loads after this file.
---Only ever called at runtime from here, so the order is fine.
Callingcards = Callingcards or {}

---@param source Source
---@param cardId string
---@return boolean
local function ownsCard(source, cardId)
    if cardId == DEFAULT_CARD_ID then
        return true
    end

    if Callingcards.isCustomCard(source, cardId) then
        return true
    end

    if not core:OwnsItem(source, cardId) then
        return false
    end

    -- Owning a seasonal card is not the same as being allowed to wear it out
    -- of season, so the window is checked separately.
    return Callingcards.isAvailable(cardId)
end

---@param source Source
---@param cardId string
local function apply(source, cardId)
    Player(source).state:set('calling_card', cardId, true)

    core:SetMetadata(source, CARD_METADATA_KEY, cardId)
end

---@param source Source
---@return string cardId
local function resolve(source)
    local data = core:GetPlayerData(source)
    local cardId = data and data.metadata and data.metadata[CARD_METADATA_KEY]

    if type(cardId) ~= 'string' or not ownsCard(source, cardId) then
        return DEFAULT_CARD_ID
    end

    return cardId
end

---@param cardId string
---@return boolean success
lib.callback.register('callingcards:server:equipCardId', function(source, cardId)
    if type(cardId) ~= 'string' then
        return false
    end

    if not ownsCard(source, cardId) then
        return false
    end

    apply(source, cardId)

    TriggerEvent('callingcards:server:onEquipped', source, cardId)

    return true
end)

---@param source Source
---@return string
exports('GetEquippedCard', function(source)
    return Player(source).state.calling_card or DEFAULT_CARD_ID
end)

---Forces a card on a player, for a reward or a staff action. Ownership is
---NOT checked: the caller is the server, and refusing it here would only
---mean the grant silently did nothing.
---@param source Source
---@param cardId string
---@return boolean
exports('SetEquippedCard', function(source, cardId)
    if type(cardId) ~= 'string' then
        return false
    end

    apply(source, cardId)

    return true
end)

---@param source Source
---@param cardId string
---@return boolean
exports('CanEquipCard', function(source, cardId)
    return ownsCard(source, cardId)
end)

-- ------------------------------------------------------------- lifecycle ----

---The equipped card has to be re-applied on every load: the statebag is
---per-session, so without this a returning player wears the default until
---they open the menu.
AddEventHandler('core:server:onPlayerLoaded', function(source)
    CreateThread(function()
        apply(source, resolve(source))

        Callingcards.pushCustomCards(source)
    end)
end)

---A card being retired mid-session leaves whoever is wearing it pointing at
---nothing, so they fall back rather than rendering a missing image.
AddEventHandler('core:onItemDeletedById', function(itemId)
    for _, playerSource in ipairs(core:GetPlayerSources()) do
        if Player(playerSource).state.calling_card == itemId then
            apply(playerSource, DEFAULT_CARD_ID)
        end
    end
end)

lib.addCommand('givecard', {
    help = 'Force a calling card onto a player',
    params = {
        { name = 'target', type = 'playerId', help = 'server id' },
        { name = 'card', type = 'string', help = 'card id' },
    },
    restricted = 'group.admin',
}, function(source, args)
    apply(args.target, args.card)

    local text = ('Set calling card %s on %s.'):format(args.card, args.target)

    -- Run from the server console there is no player to tell.
    if source == 0 then
        return print(('[callingcards] %s'):format(text))
    end

    TriggerClientEvent('gamechat:addMessage', source, {
        username = 'SERVER',
        userId = 0,
        modeId = 'announcement',
        text = text,
    })
end)
