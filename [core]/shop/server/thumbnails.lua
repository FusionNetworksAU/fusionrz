---Clothing thumbnails: /clothingshots photographs every clothing item in game
---and gives it a picture.
---
---The admin who runs it does the photographing (client/thumbnails.lua): a ped
---in the sky in front of a green panel, one shot per item, captured from the
---game frame by ui's NUI page (no screenshot resource needed). Each shot comes
---back here, is written into ui's image folder and set as the item's `image`.
---
---ui serves its files from the copy clients downloaded when it started, so new
---pictures show after `ensure ui` (the command says so when it finishes).

Shop = Shop or {}

local core = exports.core

---Where the pictures go, inside the ui resource, and the `image` value that
---points at them (ui resolves it against web/build/cdn/).
local OUTPUT_DIR = 'web/build/cdn/clothing/items/'
local IMAGE_PREFIX = 'clothing/items/'

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

    if not SaveResourceFile('ui', path, bytes, #bytes) then
        lib.print.error(('[shop] could not write ui/%s (is the ui folder writable?)'):format(path))
        return ack(false)
    end

    MySQL.update.await('UPDATE items SET image = ? WHERE id = ?', { IMAGE_PREFIX .. itemId .. '.webp', itemId })

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

    local message = ('Saved %d of %d pictures%s. Run "ensure ui" so players get the new files.'):format(
        session.saved, session.total,
        (tonumber(failed) or 0) > 0 and (' (%d could not be taken)'):format(failed) or ''
    )

    lib.print.info('[shop] ' .. message)
    TriggerClientEvent('shop:client:thumbnailNotice', source, 'success', message)
end)

AddEventHandler('playerDropped', function()
    sessions[source] = nil
end)
