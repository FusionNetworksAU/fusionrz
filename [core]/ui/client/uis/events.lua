local ui = exports.ui

local claimErrors = {
    not_live = 'This event is no longer live.',
    not_complete = 'This objective is not complete yet.',
    no_contribution = 'You did not contribute enough to collect this.',
    already_claimed = 'You already collected this reward.',
    grant_failed = 'Could not hand out the reward, try again.',
}

---@param data EventsSnapshot
exports('setEventsData', function(data)
    SendNUIMessage({ action = 'setEventsData', data = data })
end)

---@param value table<string, table<string, integer>>?
local function sendEventsProgress(value)
    SendNUIMessage({ action = 'setEventsProgress', data = value or {} })
end

AddStateBagChangeHandler('eventProgress', 'global', function(_, _, value)
    sendEventsProgress(value)
end)

AddEventHandler('uis:onReady', function()
    sendEventsProgress(GlobalState.eventProgress)
end)

---@param eventId integer
RegisterNUICallback('getEventScoreboard', function(eventId, cb)
    cb(lib.callback.await('events:server:scoreboard', false, eventId) or false)
end)

---@param data { eventId: integer, objectiveId: integer }
RegisterNUICallback('claimEventObjective', function(data, cb)
    local result = lib.callback.await('events:server:claim', false, data.eventId, data.objectiveId)

    if not result.ok then
        ui:notify({ type = 'error', text = claimErrors[result.error] })
    end

    cb(result)
end)
