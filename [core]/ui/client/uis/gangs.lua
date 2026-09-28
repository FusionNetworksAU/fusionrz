local playerState = LocalPlayer.state

---@param data table | nil
local function setGangData(data)
    SendNUIMessage({ action = 'setGangData', data = data })
end

local function pushSelfGang()
    local data = lib.callback.await('core:gangs:requestSelf', false)
    setGangData(data)
end

---@param body { gamemode?: string, cursor?: string|nil }
RegisterNUICallback('getTopCrewLeaderboard', function(body, cb)
    local gamemode = type(body) == 'table' and body.gamemode or 'hopouts'

    local snapshot = lib.callback.await('core:gangs:requestTopCrew', false, {
        gamemode = gamemode,
    })

    if not snapshot then
        cb({ gamemode = gamemode, hero = nil, entries = {}, nextCursor = nil })
        return
    end

    cb({
        gamemode   = snapshot.gamemode,
        hero       = snapshot.hero,
        entries    = snapshot.entries,
        nextCursor = nil,
    })
end)

RegisterNUICallback('getOwnGang', function(_, cb)
    local data = lib.callback.await('core:gangs:requestSelf', false)
    setGangData(data)
    cb(1)
end)

---@param body { name?: string }
RegisterNUICallback('getGangByName', function(body, cb)
    local name = type(body) == 'table' and body.name or nil
    if type(name) ~= 'string' or name == '' then
        cb(nil)
        return
    end

    local data = lib.callback.await('core:gangs:requestByName', false, {
        name = name,
    })

    cb(data)
end)

RegisterNetEvent('core:client:gangs:invalidate', function()
    pushSelfGang()
end)

---@param body { categoryId: string, itemIds: string[] }
RegisterNUICallback('purchaseGangShopItems', function(body, cb)
    if type(body) ~= 'table' then
        cb({ success = false, error = 'Invalid request' })
        return
    end

    local success, codeOrError = lib.callback.await('core:gangs:purchaseShop', false, {
        categoryId = body.categoryId,
        itemIds    = body.itemIds,
    })

    if success then
        cb({ success = true, code = codeOrError })
    else
        cb({ success = false, error = codeOrError or 'Unknown error' })
    end
end)

RegisterNUICallback('getGangShopOrders', function(_, cb)
    local result = lib.callback.await('core:gangs:getShopOrders', false) or {}
    cb({
        orders = result.orders or {},
        purchaseCounts = result.purchaseCounts or {},
        canPurchase = result.canPurchase == true,
    })
end)

CreateThread(function()
    while not playerState.uisReady do Wait(0) end
    while not playerState.isLoaded do Wait(0) end

    pushSelfGang()
end)
