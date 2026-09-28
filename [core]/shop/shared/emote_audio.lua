---Emote and store audio.
---
---Sound items name a frontend sound plus the soundset it lives in; emotes
---name an animation dictionary and clip. Both are read out of the catalogue
---row the same way, so both live here -- the client is handed the resolved
---pair and plays it, rather than being trusted with the item id.

-- The manifest loads these alphabetically, so shop.lua is not necessarily
-- first. Every file in this folder creates the table if it is not there yet.
Shop = Shop or {}
---@param item table
---@return { name: string, set: string }?
function Shop.getItemSound(item)
    local data = item.data or {}
    local name = item.soundName or data.soundName

    if not name then
        return nil
    end

    return {
        name = name,
        set = item.soundSet or data.soundSet or 'HUD_FRONTEND_DEFAULT_SOUNDSET',
    }
end

---@param item table
---@return { dictionary: string, animation: string }?
function Shop.getItemAnimation(item)
    local data = item.data or {}
    local dictionary = item.dictionary or data.dictionary
    local animation = item.animation or data.animation

    if not dictionary or not animation then
        return nil
    end

    return { dictionary = dictionary, animation = animation }
end
