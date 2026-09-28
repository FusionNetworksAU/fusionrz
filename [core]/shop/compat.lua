---Compatibility shims.
---
---car_fights applies the player's owned livery and plate to the Issi it spawns
---them into. shop owns that cosmetic state but does not expose these three in
---this base, so the car-fights enter path throws.
---
---`client/car_fights.lua` guards on `modShopLabel` being nil, so returning nil
---here simply means "no livery selected" and the vehicle spawns stock.
---Delete when the real cosmetic plumbing lands.

---Should return the mod-shop text label of the livery the player has equipped
---for this spawncode, or nil when they have none.
---@param _spawncode string
---@return string?
exports('GetSelectedLivery', function(_spawncode)
    return nil
end)

---Should apply that livery to the vehicle.
---@param _vehicle integer
---@param _spawncode string
exports('ApplySelectedVehicleSkin', function(_vehicle, _spawncode)
end)

---Should apply the player's owned plate text and index to the vehicle.
---@param _vehicle integer
exports('ApplySelectedVehiclePlate', function(_vehicle)
end)
