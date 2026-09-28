---@param data table | nil
local function setTournamentOverview(data)
    SendNUIMessage({ action = 'setTournamentOverview', data = data })
end

local function pushOverview()
    local data = lib.callback.await('core:tournaments:requestOverview', false)
    setTournamentOverview(data)
end

RegisterNUICallback('getTournamentOverview', function(_, cb)
    pushOverview()
    cb(1)
end)

---@param body { tournamentId: integer }
RegisterNUICallback('getTournamentBracket', function(body, cb)
    local tournamentId = type(body) == 'table' and body.tournamentId or nil

    local data = lib.callback.await('core:tournaments:requestBracket', false, {
        tournamentId = tournamentId,
    })

    SendNUIMessage({ action = 'setTournamentBracket', data = data })
    cb(1)
end)

---@param body { tournamentId: integer, name?: string, slots: table }
RegisterNUICallback('submitTournamentRoster', function(body, cb)
    if type(body) ~= 'table' then
        cb({ success = false, error = 'Invalid request' })
        return
    end

    local success, rosterIdOrError = lib.callback.await('core:tournaments:submitRoster', false, {
        tournamentId = body.tournamentId,
        name         = body.name,
        slots        = body.slots,
    })

    if success then
        cb({ success = true, rosterId = rosterIdOrError })
    else
        cb({ success = false, error = rosterIdOrError or 'Unknown error' })
    end
end)

---@param body { tournamentId: integer }
RegisterNUICallback('withdrawTournamentRoster', function(body, cb)
    if type(body) ~= 'table' then
        cb({ success = false, error = 'Invalid request' })
        return
    end

    local success, err = lib.callback.await('core:tournaments:withdrawRoster', false, {
        tournamentId = body.tournamentId,
    })

    if success then
        cb({ success = true })
    else
        cb({ success = false, error = err or 'Unknown error' })
    end
end)

RegisterNUICallback('getPublicTournaments', function(_, cb)
    local data = lib.callback.await('core:tournaments:requestTournaments', false)
    SendNUIMessage({ action = 'setPublicTournaments', data = data })
    cb(1)
end)

---@param body { tournamentId: integer }
RegisterNUICallback('getTournamentStandings', function(body, cb)
    local tournamentId = type(body) == 'table' and body.tournamentId or nil

    local data = lib.callback.await('core:tournaments:requestStandings', false, {
        tournamentId = tournamentId,
    })

    SendNUIMessage({ action = 'setTournamentStandings', data = data })
    cb(1)
end)

RegisterNUICallback('getTournamentManage', function(_, cb)
    local data = lib.callback.await('core:tournaments:requestManage', false)
    SendNUIMessage({ action = 'setTournamentManage', data = data })
    cb(1)
end)

---@param body { term: string }
RegisterNUICallback('tournamentSearchPlayers', function(body, cb)
    local res = lib.callback.await('core:tournaments:staff:searchPlayers', false, {
        term = type(body) == 'table' and body.term or nil,
    })
    cb(res or { players = {} })
end)

---@param body { tournamentId: integer }
RegisterNUICallback('getTournamentTeams', function(body, cb)
    local tournamentId = type(body) == 'table' and body.tournamentId or nil

    local data = lib.callback.await('core:tournaments:staff:requestTeams', false, {
        tournamentId = tournamentId,
    })

    SendNUIMessage({ action = 'setTournamentTeams', data = data })
    cb(1)
end)

---@param body { action: string }
RegisterNUICallback('tournamentStaffAction', function(body, cb)
    if type(body) ~= 'table' then
        cb({ success = false, error = 'Invalid request' })
        return
    end

    local res = lib.callback.await('core:tournaments:staff:action', false, body)
    cb(res or { success = false, error = 'No response' })
end)

RegisterNetEvent('core:client:tournaments:invalidate', function()
    pushOverview()
end)

RegisterNetEvent('core:client:tournaments:refresh', function()
    SendNUIMessage({ action = 'tournamentsRefresh' })
end)
