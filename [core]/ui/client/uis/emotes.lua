local ui = exports.ui
local shop = exports.shop

local REOPEN_COOLDOWN_MS = 400
local lastWheelCloseTime = 0
local isKeyHeld = false
local blockReopenUntilRelease = false

---@param keepFocus boolean
---@param eventName string
local function openEmoteWheel(keepFocus, eventName)
    local slots = shop:getEquippedEmoteSlots() or {}
    local slotCount = shop:getEmoteSlotCount() or 8
    local ownedEmotes = shop:getOwnedEmotes() or {}

    if slotCount <= 0 then
        lib.notify({
            title = 'No emote slots',
            description = 'Unlock slots from the profile menu.',
            type = 'error',
        })
        return
    end

    ---@type table<string, table>
    local emoteById = {}
    for _, emote in pairs(ownedEmotes) do
        emoteById[emote.emoteId] = emote
    end

    local items = {}
    for slotIndex = 1, slotCount do
        local emoteId = slots[tostring(slotIndex)]
        local emote = emoteId and emoteById[emoteId] or nil

        if emote then
            table.insert(items, {
                id = ('slot_%d'):format(slotIndex),
                label = emote.label,
                description = ('Slot %d'):format(slotIndex),
                icon = emote.image and ('https://r2.fusionrz.com/%s'):format(emote.image) or nil,
                iconInvert = true,
                event = eventName,
                eventData = slotIndex,
            })
        else
            table.insert(items, {
                id = ('slot_%d_empty'):format(slotIndex),
                label = ('SLOT %d'):format(slotIndex),
                description = 'Empty — assign one in the profile menu',
                disabled = true,
            })
        end
    end

    ui:openWheel({
        id = 'emotes',
        title = 'EMOTES',
        description = 'Pick an emote',
        maxPerPage = 12,
        items = items,
        keepFocus = keepFocus,
    })
end

local keybind = lib.addKeybind({
    name = 'emotes',
    description = 'Open Emote Wheel',
    defaultKey = 'B',
    onPressed = function()
        isKeyHeld = true

        if blockReopenUntilRelease then
            return
        end

        if ui:isWheelOpen() then
            ui:closeWheel()
            return
        end

        if GetGameTimer() - lastWheelCloseTime < REOPEN_COOLDOWN_MS then
            return
        end

        if not shop:canUseEmotes() then
            return
        end

        openEmoteWheel(false, 'ui:playEmoteSlot')
    end,
    onReleased = function()
        isKeyHeld = false
        blockReopenUntilRelease = false
    end,
})

AddEventHandler('ui:wheelClosed', function(wheelId)
    if wheelId ~= 'emotes' then return end
    lastWheelCloseTime = GetGameTimer()
    if isKeyHeld then
        blockReopenUntilRelease = true
    end
end)

---@param slotIndex integer
AddEventHandler('ui:playEmoteSlot', function(slotIndex)
    if type(slotIndex) ~= 'number' then return end
    if not shop:canUseEmotes() then return end
    shop:playEmoteSlot(slotIndex)
end)

RegisterNUICallback('openEmoteWheel', function(_, cb)
    openEmoteWheel(true, 'ranked:playEmoteSlot')
    cb(true)
end)

function GetEmotesKeybind()
    return keybind.currentKey
end