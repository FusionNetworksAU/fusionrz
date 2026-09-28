---@class UISharedConfig
local config = {
    outfitSlotPrice = 250,
    baseMaxOutfits = 10,
    outfitSlotMetadataKey = 'extra_outfit_slots',
}

---@param metadata table<string, any>
---@return integer
function config.getMaxOutfits(metadata)
    return config.baseMaxOutfits + (metadata[config.outfitSlotMetadataKey] or 0)
end

return config
