local isOpen = false

---@param visible boolean
local function setWastelandAdminVisible(visible)
    local open = visible == true
    if not open and not isOpen then
        -- nothing to close: never touch NUI focus another component may own
        return
    end
    isOpen = open
    SendNUIMessage({ action = 'setWastelandAdminVisible', data = isOpen })
    if isOpen then
        SetNuiFocus(true, true)
    elseif not IsWastelandSheetOpen() then
        SetNuiFocus(false, false)
    end
end

exports('setWastelandAdminVisible', setWastelandAdminVisible)

---@param name string
---@param ... any
---@return table
local function awaitCallback(name, ...)
    local ok, result = pcall(lib.callback.await, name, false, ...)
    if ok and type(result) == 'table' then
        return result
    end
    return { ok = false, error = 'no_response' }
end

RegisterNUICallback('closeWastelandAdmin', function(_, cb)
    cb(1)
    setWastelandAdminVisible(false)
end)

RegisterNUICallback('wastelandAdminItems', function(_, cb)
    cb(awaitCallback('wasteland:admin:items'))
end)

---@param data { shortname: string, amount: number }
RegisterNUICallback('wastelandAdminGiveItem', function(data, cb)
    cb(awaitCallback('wasteland:admin:giveItem', data))
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() or not isOpen then
        return
    end
    isOpen = false
    SetNuiFocus(false, false)
end)
