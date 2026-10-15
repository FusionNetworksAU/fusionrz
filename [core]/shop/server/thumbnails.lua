---Clothing thumbnails: /clothingshots photographs every clothing item in game
---and gives it a picture.
---
---The admin who runs it does the photographing (client/thumbnails.lua): a ped
---in the sky in front of a green panel, one shot per item, captured from the
---game frame by ui's NUI page (no screenshot resource needed). Each shot comes
---back here, is written into this resource's thumbnails/ folder and set as
---the item's `image`.
---
---Kept in shop, not in ui: the server will not write into another resource's
---folder, which is why every save into ui failed. The NUI loads them straight
---from this resource (https://cfx-nui-shop/..., listed in fxmanifest files),
---and clients get new files after `ensure shop` (the command says so).

Shop = Shop or {}

local core = exports.core

local RESOURCE = GetCurrentResourceName()

---Where the pictures go, inside this resource, and the `image` value that
---points at them. A full https URL, which the UI uses as-is.
local OUTPUT_DIR = 'thumbnails/'
local IMAGE_URL = ('https://cfx-nui-%s/thumbnails/%%s.webp'):format(RESOURCE)

---@type table<Source, { ids: table<string, true>, saved: integer, total: integer }>
local sessions = {}

local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local B64_INDEX = {}

for index = 1, #B64 do
    B64_INDEX[B64:byte(index)] = index - 1
end

---@param data string base64
---@return string bytes
local function decodeBase64(data)
    local out = {}
    local bits, count = 0, 0

    for index = 1, #data do
        local value = B64_INDEX[data:byte(index)]

        if value then
            bits = (bits << 6) | value
            count += 6

            if count >= 8 then
                count -= 8
                out[#out + 1] = string.char((bits >> count) & 0xFF)
            end
        end
    end

    return table.concat(out)
end

---@param item table
---@return boolean
local function hasOwnPicture(item)
    return type(item.image) == 'string' and item.image ~= '' and not item.image:find('^clothing/default/')
end

lib.addCommand('clothingshots', {
    help = 'Photograph clothing items for their shop and profile pictures',
    params = {
        { name = 'mode', type = 'string', help = '"missing" (default) or "all" to redo every picture', optional = true },
    },
    restricted = 'group.admin',
}, function(source, args)
    if source == 0 then
        return lib.print.warn('[shop] /clothingshots has to be run in game: the photos are taken on your screen.')
    end

    if sessions[source] then
        return TriggerClientEvent('shop:client:thumbnailNotice', source, 'error', 'Already photographing.')
    end

    local redoAll = args.mode == 'all'
    local jobs = {}
    local ids = {}

    for _, item in pairs(core:GetAllItems() or {}) do
        if item.enabled and item.category == 'clothing' and (redoAll or not hasOwnPicture(item)) then
            local slot = Shop.getClothingSlotOf(item)

            -- The id becomes a file name.
            if slot and item.id:find('^[%w_%-]+$') then
                jobs[#jobs + 1] = { id = item.id, slot = slot, apply = Shop.getClothingItemApply(item) }
                ids[item.id] = true
            end
        end
    end

    table.sort(jobs, function(a, b)
        return a.id < b.id
    end)

    if #jobs == 0 then
        return TriggerClientEvent('shop:client:thumbnailNotice', source, 'info',
            redoAll and 'There are no clothing items.' or 'Every clothing item already has a picture. Use /clothingshots all to redo them.')
    end

    sessions[source] = { ids = ids, saved = 0, total = #jobs }

    lib.print.info(('[shop] %s is photographing %d clothing items'):format(GetPlayerName(source), #jobs))
    TriggerClientEvent('shop:client:shootClothing', source, jobs)
end)

---Sent as a latent event (a picture is too big for a normal one). Each save
---is acknowledged, and the client waits for that before the next shot, so the
---"done" message can never overtake an upload still in flight.
---@param itemId string
---@param image string data URI
RegisterNetEvent('shop:server:saveThumbnail', function(itemId, image)
    local source = source --[[@as Source]]
    local session = sessions[source]

    if not session or type(itemId) ~= 'string' or not session.ids[itemId] or type(image) ~= 'string' then
        return
    end

    local function ack(ok)
        TriggerClientEvent('shop:client:thumbnailSaved', source, itemId, ok)
    end

    local base64 = image:match('^data:image/webp;base64,(.+)$')

    if not base64 then
        lib.print.warn(('[shop] thumbnail for %s was not a webp image'):format(itemId))
        return ack(false)
    end

    local bytes = decodeBase64(base64)
    local path = OUTPUT_DIR .. itemId .. '.webp'

    if not SaveResourceFile(RESOURCE, path, bytes, #bytes) then
        lib.print.error(('[shop] could not write %s/%s -- does the folder %s/thumbnails exist?'):format(
            RESOURCE, path, GetResourcePath(RESOURCE)))
        return ack(false)
    end

    MySQL.update.await('UPDATE items SET image = ? WHERE id = ?', { IMAGE_URL:format(itemId), itemId })

    session.ids[itemId] = nil
    session.saved += 1

    ack(true)
end)

---@param failed integer how many shots the client could not take
RegisterNetEvent('shop:server:thumbnailsDone', function(failed)
    local source = source --[[@as Source]]
    local session = sessions[source]

    if not session then
        return
    end

    sessions[source] = nil

    -- New `image` values into the catalogue, and to every player's menus.
    core:RefreshItems()

    local message = ('Saved %d of %d pictures%s. Run "ensure shop" so players get the new files.'):format(
        session.saved, session.total,
        (tonumber(failed) or 0) > 0 and (' (%d could not be taken)'):format(failed) or ''
    )

    lib.print.info('[shop] ' .. message)
    TriggerClientEvent('shop:client:thumbnailNotice', source, 'success', message)
end)

AddEventHandler('playerDropped', function()
    sessions[source] = nil
end)
