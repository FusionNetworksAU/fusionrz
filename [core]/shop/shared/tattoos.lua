---Tattoo zones.
---
---A tattoo occupies one of the six zones in config/data.lua, and a zone holds
---one tattoo. The store sends a zone name with every equip, so this is what
---decides whether that name is real.

-- The manifest loads these alphabetically, so shop.lua is not necessarily
-- first. Every file in this folder creates the table if it is not there yet.
Shop = Shop or {}
---@type table<string, true>
local zones = {}

for index = 1, #Shop.data.tattooZones do
    zones[Shop.data.tattooZones[index]] = true
end

---@param zone string?
---@return boolean
function Shop.isTattooZone(zone)
    return zone ~= nil and zones[zone] == true
end

---@return string[]
function Shop.getTattooZones()
    return Shop.data.tattooZones
end

---The zone a tattoo item belongs to. Items carry it in their catalogue data;
---anything without one is treated as torso, which is where the majority sit.
---@param item table
---@return string
function Shop.getTattooZone(item)
    local data = item.data or {}
    local zone = item.zone or data.zone

    return Shop.isTattooZone(zone) and zone or 'torso'
end
