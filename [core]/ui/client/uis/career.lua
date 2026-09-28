local playerState = LocalPlayer.state

---@param modeType RankedModeType
RegisterNUICallback('fetchCareerRanks', function(modeType, cb)
    TriggerServerEvent('career:server:fetchRanks', modeType)
    cb(1)
end)

RegisterNUICallback('getMatchHistory', function(data, cb)
    local history = lib.callback.await('career:server:getMatchHistoryData', false, data)

    cb(history)
end)

---@param payload { gamemode: string, userId: number? }
RegisterNUICallback('getCareerStats', function(payload, cb)
    local data = lib.callback.await('career:server:getStats', false, payload)

    cb(data)
end)

---@param data { metric: string, range: string }
RegisterNUICallback('getCareerStatSeries', function(data, cb)
    local response = lib.callback.await('career:server:getStatSeries', false, data)

    cb(response)
end)

RegisterNUICallback('getCareerData', function(payload, cb)
    local data = lib.callback.await('career:server:getData', false, payload)

    cb(data)
end)

---@param payload { gamemode: string, userId: number? }
RegisterNUICallback('getCareerRankOverview', function(payload, cb)
    local data = lib.callback.await('career:server:getRankOverview', false, payload)

    cb(data)
end)

---@param input string
RegisterNUICallback('savePersonalBio', function(input, cb)
    local success, err = lib.callback.await('ui:server:setPersonalBio', false, input)

    if not success then
        lib.print.error(err)
        exports.ui:notify({ type = 'error', text = err })
    end

    cb(success)
end)

---@param payload { country: string }
RegisterNUICallback('saveCareerCountry', function(payload, cb)
    local success, err = lib.callback.await('ui:server:setCareerCountry', false, payload)

    if not success and err then
        exports.ui:notify({ type = 'error', text = err })
    end

    cb(success)
end)

---@param payload { matchId: number, userId: number? }
RegisterNUICallback('getCareerMatchDetails', function(payload, cb)
    local data = lib.callback.await('career:server:getMatchDetails', false, payload)

    cb(data)
end)

---@param ranks table
RegisterNetEvent('career:client:setRanks', function(ranks)
    -- The server sends { gamemode = ..., ranks = { ... } }, but the ranks panel
    -- puts this straight into its state and slices it into tiers, so it wants
    -- the array itself. Forwarding the wrapper made it throw
    -- "slice is not a function". Both shapes are accepted so the server side
    -- can be tidied up separately without breaking this.
    if type(ranks) == 'table' and ranks.ranks ~= nil then
        ranks = ranks.ranks
    end

    SendNUIMessage({
        action = 'setCareerRanks',
        data = ranks,
    })
end)

---@param history table
RegisterNetEvent('career:client:setMatchHistory', function(history)
    SendNUIMessage({
        action = 'setCareerMatchHistory',
        data = history,
    })
end)

---@param key string
---@param value any
RegisterNetEvent('core:client:onSetMetadata', function(key, value)
    if key ~= 'personal_bio' then
        return
    end

    SendNUIMessage({
        action = 'setPersonalBio',
        data = value,
    })
end)

CreateThread(function()
    while not playerState.uisReady do
        Wait(0)
    end

    while not playerState.isLoaded do
        Wait(0)
    end

    SendNUIMessage({ action = 'setPersonalBio', data = PlayerData.metadata.personal_bio or '' })
end)