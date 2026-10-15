---Lifecycle, and the one pull the client makes.
---
---Everything the profile menu renders is an export on `ui`, which is a client
---resource -- so the server cannot call any of them. The pattern is therefore
---pull, not push: the server says "your data changed", the client asks for
---the snapshot shared/profile.lua builds, and the client fans it out.

---@return table?
lib.callback.register('shop:server:getProfileData', function(source)
    return Shop.buildProfile(source)
end)

---@param source Source
local function syncPlayer(source)
    Shop.pushAll(source)
    Shop.pushStore(source)
    Shop.pushGifts(source)
    Shop.pushCreatorSelfInfo(source)
end

AddEventHandler('core:server:onPlayerLoaded', function(source)
    -- No token count yet means new to the shop rather than out of tokens, so
    -- the starting grant is written once, here.
    if Shop.get(source, Shop.keys.refundTokens, nil) == nil then
        Shop.set(source, Shop.keys.refundTokens, Shop.tuning.refunds.startingTokens)
    end

    syncPlayer(source)
end)

---@type table<Source, integer> last sync per player, GetGameTimer
local lastSync = {}

---The push above happens once, at load, and is lost if the NUI page was not
---up yet -- or entirely after `ensure shop`, since nobody loads again. The
---client asks again whenever the UI becomes ready or a menu opens.
RegisterNetEvent('shop:server:requestSync', function()
    local source = source --[[@as Source]]

    if not Shop.getUserId(source) then
        return
    end

    local now = GetGameTimer()

    if lastSync[source] and now - lastSync[source] < 2000 then
        return
    end

    lastSync[source] = now

    syncPlayer(source)
end)

AddEventHandler('playerDropped', function()
    lastSync[source] = nil
end)

---Says on startup whether there is anything to sell, because an empty
---catalogue looks exactly like a broken store from the menu.
CreateThread(function()
    local core = exports.core

    while not core:AreItemsReady() do
        Wait(500)
    end

    local forSale, free = 0, 0

    for _, item in pairs(core:GetAllItems() or {}) do
        if item.enabled and item.purchasable and (item.price or 0) > 0 then
            forSale += 1
        end

        if item.enabled and item.free then
            free += 1
        end
    end

    if forSale == 0 then
        lib.print.warn('[shop] the store has nothing to sell: no enabled, purchasable, priced rows in `items`. Run core/shop_weapons.sql (or add your own rows), then /refreshitems.')
    else
        lib.print.info(('[shop] %d items for sale'):format(forSale))
    end

    if free == 0 then
        lib.print.warn('[shop] no free clothing: run shop/default_clothing.sql, then /refreshitems.')
    else
        lib.print.info(('[shop] %d free clothing pieces'):format(free))
    end
end)
