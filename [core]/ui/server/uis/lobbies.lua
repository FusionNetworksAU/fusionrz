---Lobby map list.
---
---ui/client/uis/lobbies.lua builds the freeroam half of the list itself out
---of core/data/locations.lua, then asks here for the ranked half. Ranked
---lobbies run on hopouts, so its map table is the source -- ui stores no map
---data of its own.
---
---The payload is deflate-compressed JSON because that is what the client
---already decodes (LibDeflate:DecompressDeflate then json.decode). A map list
---is mostly repeated keys, so it compresses hard, and this is sent to every
---player as their UI comes up.

local LibDeflate = require '@core.modules.deflate'

---@class LobbyMapEntry
---@field id string
---@field label string
---@field desc string?
---@field image string?

---Built once. Maps are static data loaded from a file at resource start, so
---rebuilding this per player would be the same string every time.
---@type string?
local payload

---@return string
local function buildPayload()
    ---@type LobbyMapEntry[]
    local maps = {}

    if GetResourceState('hopouts') == 'started' then
        local hopoutsMaps = require '@hopouts.data.maps'
        -- A hopouts map has no blurb of its own, but the ones built on a
        -- core location share its id, so the lobby card can borrow that
        -- location's description rather than render an empty panel.
        local locations = require '@core.data.locations'

        for id, map in pairs(hopoutsMaps) do
            if map.enabled then
                local location = locations[map.id or id]

                maps[#maps + 1] = {
                    id = map.id or id,
                    label = map.label,
                    desc = map.description or (location and location.description) or nil,
                    image = map.image or (location and location.image) or nil,
                }
            end
        end

        table.sort(maps, function(a, b)
            return a.label < b.label
        end)
    end

    -- json.encode of an empty table gives `{}`, which json.decode hands back
    -- as a table the client can still iterate -- so an empty ranked list is
    -- not a special case on either side.
    return LibDeflate:CompressDeflate(json.encode(maps))
end

---@return string deflate-compressed JSON of LobbyMapEntry[]
lib.callback.register('uis:server:getRankedLobbyMaps', function()
    payload = payload or buildPayload()

    return payload
end)

---Lets hopouts drop the cache if its map table is ever reloaded.
exports('RefreshRankedLobbyMaps', function()
    payload = nil
end)
