---Which optional tables actually exist.
---
---ui reads tables owned by other resources -- `user_game_stats` from misc,
---`ranked_elo` and friends from ranked -- and those are imported by hand. A
---query against a missing table throws, ox_lib catches it, and the client is
---handed nil. The NUI then does `players.map(...)` on undefined and the whole
---page dies, which is a far worse failure than an empty board.
---
---So every such query is gated on this. The answer is cached because it can
---only change when someone imports a file, and the cache is cleared by
---`/uirecheckschema` for exactly that case.
---
---Loaded before the rest of server/uis/*.lua: the glob is alphabetical and
---'_' sorts ahead of the lowercase filenames.

Schema = {}

---@type table<string, boolean>
local known = {}

---@param name string
---@return boolean
function Schema.has(name)
    if known[name] ~= nil then
        return known[name]
    end

    local exists = MySQL.scalar.await([[
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = DATABASE() AND table_name = ?
    ]], { name }) ~= nil

    known[name] = exists

    if not exists then
        lib.print.warn(('[ui] `%s` does not exist; the pages that read it will render empty'):format(name))
    end

    return exists
end

---Every table in the list has to be there for the caller to go ahead.
---@param ... string
---@return boolean
function Schema.hasAll(...)
    local names = { ... }

    for index = 1, #names do
        if not Schema.has(names[index]) then
            return false
        end
    end

    return true
end

function Schema.clear()
    table.wipe(known)
end

lib.addCommand('uirecheckschema', {
    help = 'Re-check which optional tables exist, after importing a .sql file',
    restricted = 'group.admin',
}, function()
    Schema.clear()

    lib.print.info('[ui] schema cache cleared')
end)
