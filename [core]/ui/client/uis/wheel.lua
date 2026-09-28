---@class WheelItem
---@class WheelData
--- (See ui/types.lua for the authoritative definitions.)

local isOpen = false
---@type { id: string, items: table<string, WheelItem>, keepFocus: boolean } | nil
local currentWheel = nil

---@param data WheelData
---@return boolean opened
local function openWheel(data)
    assert(type(data) == 'table', 'openWheel: data must be a table')
    assert(type(data.id) == 'string', 'openWheel: data.id must be a string')
    assert(type(data.items) == 'table' and #data.items > 0,
        'openWheel: data.items must be a non-empty array')

    local nuiItems = {}
    local lookup = {}

    for i = 1, #data.items do
        local item = data.items[i]
        assert(type(item.id) == 'string', ('openWheel: items[%d].id must be a string'):format(i))
        assert(type(item.label) == 'string', ('openWheel: items[%d].label must be a string'):format(i))
        assert(lookup[item.id] == nil, ('openWheel: duplicate item id "%s"'):format(item.id))

        lookup[item.id] = item
        nuiItems[i] = {
            id = item.id,
            label = item.label,
            description = item.description,
            icon = item.icon,
            iconInvert = item.iconInvert,
            disabled = item.disabled,
        }
    end

    currentWheel = {
        id = data.id,
        items = lookup,
        keepFocus = data.keepFocus or false,
    }

    SendNUIMessage({
        action = 'setWheelData',
        data = {
            id = data.id,
            title = data.title,
            description = data.description,
            maxPerPage = data.maxPerPage,
            items = nuiItems,
        }
    })

    if not isOpen then
        SendNUIMessage({ action = 'setWheelVisible', data = true })
        SetNuiFocus(true, true)
        -- Center the cursor so each open starts at the wheel's middle (muscle memory).
        SetCursorLocation(0.5, 0.5)
        isOpen = true
    end

    return true
end

exports('openWheel', openWheel)

local function closeWheel()
    if not isOpen then
        return
    end

    local closedId = currentWheel and currentWheel.id or nil

    SendNUIMessage({ action = 'setWheelVisible', data = false })
    if not currentWheel?.keepFocus then
        SetNuiFocus(false, false)
    end

    isOpen = false
    currentWheel = nil

    TriggerEvent('ui:wheelClosed', closedId)
end

exports('closeWheel', closeWheel)

---@return boolean isOpen
---@return string? wheelId Id of the currently open wheel, if any.
local function isWheelOpen()
    return isOpen, currentWheel and currentWheel.id or nil
end

exports('isWheelOpen', isWheelOpen)

RegisterNUICallback('closeWheel', function(_, cb)
    cb(1)
    closeWheel()
end)

---@param data { wheelId: string, itemId: string }
RegisterNUICallback('selectWheelItem', function(data, cb)
    cb(1)

    local wheel = currentWheel
    if not wheel or not data or wheel.id ~= data.wheelId then
        print(('selectWheelItem: invalid wheelId "%s"'):format(data and data.wheelId or 'nil'))
        closeWheel()
        return
    end

    local item = wheel.items[data.itemId]

    closeWheel()

    if not item or item.disabled then
        return print(('selectWheelItem: invalid or disabled itemId "%s"'):format(data.itemId))
    end

    print(('Selected itemId "%s" from wheelId "%s"'):format(data.itemId, data.wheelId))

    if item.event then
        print(('Triggering client event "%s" for itemId "%s"'):format(item.event, item.id))
        TriggerEvent(item.event, item.eventData, item)
    end

    if item.serverEvent then
        print(('Triggering server event "%s" for itemId "%s"'):format(item.serverEvent, item.id))
        TriggerServerEvent(item.serverEvent, item.eventData)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        closeWheel()
    end
end)
