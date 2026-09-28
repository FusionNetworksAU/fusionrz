---Career / settings callbacks.
---
---ui/fxmanifest.lua has always declared server_scripts { 'server/uis/*.lua' }
---but the directory did not exist, so every one of these raised
---"callback does not exist" on the client. Everything here is backed by
---core's exports -- ui stores nothing of its own.

local core = exports.core

local MAX_BIO_LENGTH = 240

---@param source number
---@return table?
local function getMetadata(source)
    local data = core:GetPlayerData(source)

    return data and data.metadata or nil
end

---@param input string
---@return boolean success
---@return string? error
lib.callback.register('ui:server:setPersonalBio', function(source, input)
    if type(input) ~= 'string' then
        return false, 'Invalid bio.'
    end

    local bio = input:gsub('^%s+', ''):gsub('%s+$', '')

    if #bio > MAX_BIO_LENGTH then
        return false, ('Your bio must be at most %s characters.'):format(MAX_BIO_LENGTH)
    end

    if core:ContainsProfanity(bio) then
        return false, 'Your bio contains profanities.'
    end

    if not core:SetMetadata(source, 'personal_bio', bio) then
        return false, 'No player loaded.'
    end

    return true
end)

---@param payload { country: string }
---@return boolean success
---@return string? error
lib.callback.register('ui:server:setCareerCountry', function(source, payload)
    if type(payload) ~= 'table' or type(payload.country) ~= 'string' then
        return false, 'Invalid country.'
    end

    return core:SetCountry(source, payload.country)
end)

---Name colours are `chat_colors` items the player owns. The list the UI
---renders is therefore their inventory filtered to that category, not a
---hardcoded palette.
---@return table[] nameColors
---@return string? nameColorForUi
lib.callback.register('ui:server:getNameColors', function(source)
    local owned = core:GetUsableTypeIds(source)
    local metadata = getMetadata(source)

    ---@type table[]
    local nameColors = {}

    for index = 1, #owned do
        local item = core:GetItem(owned[index])

        if item and item.category == 'chat_colors' then
            nameColors[#nameColors + 1] = {
                id = item.id,
                label = item.label,
                colour = item.colour or item.data and item.data.colour,
            }
        end
    end

    return nameColors, metadata and metadata.name_color or nil
end)

---@param colorId string
---@return boolean success
lib.callback.register('ui:server:setNameColor', function(source, colorId)
    if colorId == nil or colorId == '' then
        return core:SetMetadata(source, 'name_color', nil)
    end

    if type(colorId) ~= 'string' or not core:OwnsItem(source, colorId) then
        return false
    end

    return core:SetMetadata(source, 'name_color', colorId)
end)

---Chat text colour draws from the same `chat_colors` catalogue as the name
---colour: the NUI paints one on the sender's name and the other on the
---message body, but a player owns one list of colours, not two. Kept under
---its own metadata key so picking a body colour does not move their name
---colour with it.
---@return table[] options
---@return string? equippedId
lib.callback.register('ui:server:getChatTextColors', function(source)
    local owned = core:GetUsableTypeIds(source)
    local metadata = getMetadata(source)

    ---@type table[]
    local options = {}

    for index = 1, #owned do
        local item = core:GetItem(owned[index])

        if item and item.category == 'chat_colors' then
            options[#options + 1] = {
                id = item.id,
                label = item.label,
                colour = item.colour or item.data and item.data.colour,
            }
        end
    end

    return options, metadata and metadata.chat_text_color or nil
end)

---@param colorId string?
---@return boolean success
lib.callback.register('ui:server:setChatTextColor', function(source, colorId)
    if colorId == nil or colorId == '' then
        return core:SetMetadata(source, 'chat_text_color', nil)
    end

    if type(colorId) ~= 'string' or not core:OwnsItem(source, colorId) then
        return false
    end

    return core:SetMetadata(source, 'chat_text_color', colorId)
end)

---chat-tags.lua indexes the result (`data.tags`), so this must never return
---nil even when the player owns nothing.
---@return { tags: table[], activeTag: string? }
lib.callback.register('ui:server:getChatTagsData', function(source)
    local owned = core:GetUsableTypeIds(source)
    local metadata = getMetadata(source)

    ---@type table[]
    local tags = {}

    for index = 1, #owned do
        local item = core:GetItem(owned[index])

        if item and item.category == 'chat_colors' then
            tags[#tags + 1] = {
                id = item.id,
                name = item.label,
                label = item.label,
                colour = item.colour or item.data and item.data.colour,
            }
        end
    end

    return {
        tags = tags,
        activeTag = metadata and metadata.chat_tag or nil,
    }
end)

---@param name string
---@return boolean success
lib.callback.register('ui:server:setActiveChatTag', function(source, name)
    if type(name) ~= 'string' or not core:OwnsItem(source, name) then
        return false
    end

    return core:SetMetadata(source, 'chat_tag', name)
end)

---@return boolean success
lib.callback.register('ui:server:unsetActiveChatTag', function(source)
    return core:SetMetadata(source, 'chat_tag', nil)
end)

---Which ace-gated weapons this player may see in the global weapon list.
---ui/client/main.lua merges this with the item-backed aces itself, so all
---that is needed here is the plain ace check per weapon.
---@return table<string, boolean>
lib.callback.register('ui:server:getGlobalWeaponAces', function(source)
    ---@type table<string, boolean>
    local allowed = {}

    for weaponName, weaponData in pairs(core:GetWeaponsWithAce()) do
        allowed[weaponName] = IsPlayerAceAllowed(source --[[@as string]], weaponData.ace)
    end

    return allowed
end)
