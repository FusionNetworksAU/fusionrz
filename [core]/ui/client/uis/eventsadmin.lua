---@param visible boolean
local function setEventsAdminVisible(visible)
    SendNUIMessage({ action = 'setEventsAdminVisible', data = visible })
    SetNuiFocus(visible, visible)
end

exports('setEventsAdminVisible', setEventsAdminVisible)

RegisterNUICallback('closeEventsAdmin', function(_, cb)
    cb(1)

    setEventsAdminVisible(false)
end)

RegisterNUICallback('adminEventsList', function(_, cb)
    cb(lib.callback.await('events:admin:list', false))
end)

---@param eventId number
RegisterNUICallback('adminEventGet', function(eventId, cb)
    cb(lib.callback.await('events:admin:get', false, eventId))
end)

---@param draft table
RegisterNUICallback('adminEventSave', function(draft, cb)
    cb(lib.callback.await('events:admin:save', false, draft))
end)

---@param body { eventId: number, startsAtIso: string?, endsAtIso: string }
RegisterNUICallback('adminEventPublish', function(body, cb)
    cb(lib.callback.await('events:admin:publish', false, body.eventId, body.startsAtIso, body.endsAtIso))
end)

---@param eventId number
RegisterNUICallback('adminEventEnd', function(eventId, cb)
    cb(lib.callback.await('events:admin:end', false, eventId))
end)

---@param eventId number
RegisterNUICallback('adminEventArchive', function(eventId, cb)
    cb(lib.callback.await('events:admin:archive', false, eventId))
end)

---@param eventId number
RegisterNUICallback('adminEventDelete', function(eventId, cb)
    cb(lib.callback.await('events:admin:delete', false, eventId))
end)

---@param body { search: string }
RegisterNUICallback('adminEventItems', function(body, cb)
    cb(lib.callback.await('events:admin:items', false, body.search))
end)

RegisterNUICallback('eventUploadTarget', function(_, cb)
    cb(lib.callback.await('events:admin:uploadUrl', false))
end)
