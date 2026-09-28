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

AddEventHandler('core:server:onPlayerLoaded', function(source)
    -- No token count yet means new to the shop rather than out of tokens, so
    -- the starting grant is written once, here.
    if Shop.get(source, Shop.keys.refundTokens, nil) == nil then
        Shop.set(source, Shop.keys.refundTokens, Shop.tuning.refunds.startingTokens)
    end

    Shop.pushAll(source)
    Shop.pushStore(source)
    Shop.pushGifts(source)
    Shop.pushCreatorSelfInfo(source)
end)
