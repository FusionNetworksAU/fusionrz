---Crew/gang callbacks.
---
---NOT IMPLEMENTED. There is no gang system in this server yet, but the UI
---(ui/client/uis/gangs.lua) calls these on every menu open, and an
---unregistered ox_lib callback raises a script error on the client rather
---than returning quietly.
---
---These return the empty shape each caller expects so the UI renders its
---"no crew" state. Replace the bodies when the gang system lands; the
---signatures are what the UI already relies on.

lib.callback.register('core:gangs:requestSelf', function()
    return nil
end)

---@return { gamemode: string, hero: table?, entries: table[], nextCursor: string? }
lib.callback.register('core:gangs:requestTopCrew', function(_, body)
    return {
        gamemode = type(body) == 'table' and body.gamemode or 'hopouts',
        hero = nil,
        entries = {},
        nextCursor = nil,
    }
end)

lib.callback.register('core:gangs:requestByName', function()
    return nil
end)

---@return { orders: table[], purchaseCounts: table, canPurchase: boolean }
lib.callback.register('core:gangs:getShopOrders', function()
    return {
        orders = {},
        purchaseCounts = {},
        canPurchase = false,
    }
end)

---@return boolean success
---@return string? error
lib.callback.register('core:gangs:purchaseShop', function()
    return false, 'Crew shops are not available yet.'
end)
